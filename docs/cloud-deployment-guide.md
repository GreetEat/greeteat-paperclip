# Deploying Paperclip to Google Cloud Run — A Field Guide

> **Status**: battle-tested on 2026-04-11/12. Running in production at
> `paperclip-492823` with Claude Opus 4.6 via Vertex AI.
>
> **Audience**: operators who want to run Paperclip in the cloud (not
> just on a laptop). Assumes familiarity with Terraform, GCP, and
> Paperclip's basic concepts.

## Why this guide exists

Paperclip is designed for local-first developer use. Its architecture
assumes a **persistent local filesystem** (Docker volume on a laptop),
a **single user** (the developer), and **direct terminal access** to the
running process. These assumptions break on Cloud Run (and any other
stateless compute platform) in predictable but non-obvious ways.

We deployed Paperclip to GCP Cloud Run with:

- Public authenticated mode (`PAPERCLIP_DEPLOYMENT_MODE=authenticated`,
  `PAPERCLIP_DEPLOYMENT_EXPOSURE=public`)
- Claude Opus 4.6 / Sonnet 4.6 via Vertex AI (no Anthropic API key)
- Cloud SQL for PostgreSQL 17 (private IP, regional HA)
- GCS for file storage (S3 interop API + HMAC keys)
- GCS FUSE for persistent `/paperclip` state volume
- GitHub Actions + WIF for CI image builds

This document captures everything we learned, broke, and fixed along
the way.

---

## The core mismatch: local-first vs. stateless compute

| Paperclip assumes | Cloud Run provides |
|---|---|
| Persistent Docker volume at `/paperclip` | Per-instance ephemeral tmpfs |
| Single user (the developer) | Multiple instances, no shared state |
| `~/.paperclip/` persists between runs | Fresh filesystem on every scale event |
| `paperclipai` CLI is on PATH | CLI is a pnpm script, not a binary |
| Terminal access to the running process | No exec, no SSH, no TTY |
| `disableSignUp=false` is fine (it's your laptop) | Open signup = published RCE exploit chain |

Every workaround below addresses one of these mismatches.

---

## Workaround 1: GCS FUSE mount at `/paperclip`

**Problem**: agent instructions, PARA memory, workspace files, and
config.json are written to `/paperclip` which is ephemeral. Agents
lose all state on instance recycle.

**Solution**: mount a GCS bucket at `/paperclip` via Cloud Run v2's
native GCS FUSE volume support.

```hcl
# In the Cloud Run service spec:
volumes {
  name = "paperclip-state"
  gcs {
    bucket    = "your-project-state-bucket"
    read_only = false
  }
}
containers {
  volume_mounts {
    name       = "paperclip-state"
    mount_path = "/paperclip"
  }
}
```

The runtime SA needs `roles/storage.objectUser` on the bucket.

**Performance note**: GCS FUSE adds ~10-50ms latency on metadata
operations. For Paperclip's use case (small text files — agent
instructions, PARA YAML, daily notes), this is imperceptible. File
locking is NOT supported — but each agent writes to its own subtree,
so concurrent write conflicts are rare.

---

## Workaround 2: Bootstrap-ceo wrapper script

**Problem**: `paperclipai auth bootstrap-ceo` refuses to run without a
config file at `PAPERCLIP_CONFIG`
(`/paperclip/instances/default/config.json`). The CLI was designed for
laptops where `~/.paperclip` persists; Cloud Run Jobs start with
empty filesystems.

**Solution**: a wrapper shell script that materializes a minimal valid
`config.json` from env vars before exec'ing the CLI.

```sh
#!/bin/sh
set -e
mkdir -p "$(dirname "$PAPERCLIP_CONFIG")"
cat > "$PAPERCLIP_CONFIG" <<'JSON'
{
  "$meta": { "version": 1, "updatedAt": "1970-01-01T00:00:00Z", "source": "configure" },
  "database": { "mode": "postgres", "connectionString": "placeholder" },
  "logging": { "mode": "cloud" },
  "server": { "deploymentMode": "authenticated", "exposure": "public",
              "host": "0.0.0.0", "port": 3100 },
  "auth": { "baseUrlMode": "explicit",
            "publicBaseUrl": "YOUR_PUBLIC_URL" }
}
JSON
exec node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts \
  auth bootstrap-ceo --base-url "YOUR_PUBLIC_URL"
```

**Cloud Run Job CMD note**: leave `command` UNSET so the upstream
Docker ENTRYPOINT (`docker-entrypoint.sh` -> `gosu node`) stays in
place. Put the actual invocation in `args` only. Setting `command`
replaces the entrypoint and breaks UID/GID remapping.

---

## Workaround 3: The bootstrap dance (first user creation)

**Problem**: `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` blocks the
GHSA-68qg-g8mg-6pr7 RCE exploit chain (which is critical for any
public deployment), but it ALSO blocks the first user creation. The
`bootstrap-ceo` invite promotes a signed-in user to instance_admin —
it doesn't create the account.

**Solution**: a 5-step dance:

1. Run bootstrap-ceo Cloud Run Job → mint invite URL
2. Temporarily flip `PAPERCLIP_AUTH_DISABLE_SIGN_UP=false` via
   `gcloud run services update --update-env-vars`
3. Invitee signs up at the invite URL → account created
4. Invitee clicks "Accept bootstrap invite" → promoted to admin
5. `terraform apply` to revert env var to `true` (Terraform state
   is the source of truth)

**Vulnerability window**: steps 2-5. Mitigation: don't broadcast the
Cloud Run URL during this window. Move fast.

**This same dance is required for EVERY new user** because there's no
UI for human invites and Better Auth's `disableSignUp` is a blanket
flag with no per-invite bypass.

---

## Workaround 4: DATABASE_URL needs `?sslmode=require`

**Problem**: Cloud SQL with `ssl_mode = ENCRYPTED_ONLY` requires TLS.
The `postgres` npm package (postgres.js) that Paperclip uses does NOT
auto-negotiate SSL on private-IP connections.

**Solution**: append `?sslmode=require` to the connection string in
the database URL secret:

```
postgres://paperclip:<pw>@<private_ip>:5432/paperclip?sslmode=require
```

Without this, Cloud SQL's `pg_hba.conf` rejects the auth handshake
and Paperclip exits(1) before binding the port:

```
PostgresError: pg_hba.conf rejects connection for host "10.8.0.x",
  user "paperclip", database "paperclip", no encryption
```

---

## Workaround 5: Vertex partner model features org policy

**Problem**: some GCP organizations enforce a `denyAll` policy on
`constraints/vertexai.allowedPartnerModelFeatures`, which blocks
Claude's built-in `web_search` tool. Agents fall back to shelling out
to `curl` to fetch web pages.

**Solution**: project-level org policy override:

```yaml
name: projects/YOUR_PROJECT/policies/vertexai.allowedPartnerModelFeatures
spec:
  rules:
  - values:
      allowedValues:
      - publishers/anthropic/models/claude-opus-4-6:web_search
      - publishers/anthropic/models/claude-sonnet-4-6:web_search
      - publishers/anthropic/models/claude-haiku-4-5:web_search
```

Requires `roles/orgpolicy.policyAdmin` granted at the org level (not
project level — the role is not grantable on projects).

---

## Workaround 6: No human invite UI

**Problem**: the Paperclip dashboard only has invite-creation UI for
OpenClaw agents, not human board users. The API supports it; the UI
doesn't expose it.

**Solution**: call the API from the browser dev tools:

```js
fetch("/api/companies/YOUR_COMPANY_ID/invites", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ allowedJoinTypes: "human" }),
})
  .then(r => r.json())
  .then(j => console.log("Invite URL:", location.origin + j.inviteUrl));
```

Approve pending join requests the same way:

```js
fetch("/api/companies/YOUR_COMPANY_ID/join-requests?status=pending_approval")
  .then(r => r.json()).then(console.log);

// then:
fetch("/api/companies/YOUR_COMPANY_ID/join-requests/REQ_ID/approve",
  { method: "POST", headers: {"Content-Type":"application/json"}, body: "{}" })
  .then(r => r.json()).then(console.log);
```

---

## Workaround 7: Managed instructions not DB-backed

**Problem**: in "managed" bundle mode, Paperclip writes agent
instructions (AGENTS.md, HEARTBEAT.md, SOUL.md, TOOLS.md) to disk at
agent creation time. Without a persistent volume, the files are lost
on the first instance recycle. The dashboard shows "Instructions root
does not exist."

**Solution**: the GCS FUSE mount (Workaround 1) fixes this going
forward. But if agents were created BEFORE the mount existed, you need
to manually restore the files. Paperclip's default templates live at:

- `server/src/onboarding-assets/ceo/` — CEO-specific templates
- `server/src/onboarding-assets/default/` — generic template

Write them to the correct GCS path:
`gs://YOUR_STATE_BUCKET/instances/prod/companies/COMPANY_ID/agents/AGENT_ID/instructions/`

---

## Upstream issues worth filing

These are real product gaps in Paperclip that affect every
authenticated cloud deployment, not just GCP:

1. **bootstrap-ceo CLI requires a config file that may not exist**
   (issue #87 is related). The CLI should prefer env vars over the
   config-file existence check.

2. **"Managed" instructions bundle should be DB-backed**, not
   disk-only. Agents shouldn't lose their persona and heartbeat
   checklist because a container recycled.

3. **No UI for creating human user invites.** The API exists; the
   dashboard doesn't expose it. Every multi-user deployment needs
   this.

4. **`disableSignUp` has no per-invite bypass.** The bootstrap-ceo
   invite should let the invitee create an account in the same flow,
   so operators don't need the temporary-flip dance.

5. **Cloud Run deployment guide in upstream docs.** Paperclip's docs
   cover Docker and local-first deployment but not stateless compute
   platforms.

---

## GCP architecture diagram (text)

```
Internet
  |
  v
Cloud Run service (paperclip)
  |- min_instances=2, public ingress
  |- runtime SA: paperclip-runtime-sa
  |- VPC connector -> Cloud SQL private IP
  |- GCS FUSE mount at /paperclip -> gs://PROJECT-state
  |- Secrets mounted from Secret Manager:
  |    MASTER_KEY, BETTER_AUTH_SECRET, DATABASE_URL,
  |    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  |- Vertex AI Claude via CLAUDE_CODE_USE_VERTEX=1
  |
Cloud SQL (PostgreSQL 17, private IP, REGIONAL HA)
  |
GCS uploads bucket (S3 interop via HMAC keys)
  |
GCS state bucket (GCS FUSE persistent /paperclip)
  |
Cloud Run Job (bootstrap-ceo)
  |- same image, SA, VPC, secrets
  |- wrapper script materializes config.json
  |
GitHub Actions (build-image.yml)
  |- WIF auth, clones upstream, builds, Trivy scan, pushes to AR
```

---

## Credits

Deployed by the GreetEat team using Claude Code (Anthropic) for
infrastructure-as-code generation and debugging. The full deployment
spec (60+ tasks, 20 research decisions, operator quickstart) lives at
`specs/001-deploy-gcp-public-auth/` in the greeteat-paperclip repo.
