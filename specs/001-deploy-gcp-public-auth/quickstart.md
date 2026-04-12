# Quickstart: First Deploy of GreetEat Paperclip on GCP

**Audience**: A platform operator deploying GreetEat Paperclip into the
shared `paperclip-492823` GCP project for the first time, OR after a
destructive teardown.
**Outcome**: A working public Paperclip endpoint where US1, US2, and US3
acceptance scenarios all pass.
**Time**: ~60–90 minutes for the first deploy (most of it waiting for
Cloud SQL provisioning), ~10 minutes for each subsequent deploy.

This walkthrough is the source of truth for SC-004 ("authorized operator
can complete a full deploy producing a working public endpoint within a
single working session, with no manual console steps").

---

## 0. Before you start

**You need:**

- Active GCP authentication as an account with `roles/owner` on
  `paperclip-492823` (Victor confirmed on 2026-04-10)
- `gcloud` CLI installed and authenticated
- `terraform` CLI installed (version pinned in `.tool-versions` /
  `terraform-version`)
- A registered domain (or subdomain you control) for the public
  hostname — you will need to point a DNS record at Cloud Run's
  `ghs.googlehosted.com`
- The Paperclip release tag you want to deploy (e.g. `v0.42.0`)
- Vertex AI Claude Sonnet 4.6 enabled in the project's Model Garden
  (one-time, already done on 2026-04-10 — verify with the test in
  Section 1c)

**You do NOT need:**

- A new GCP project (we use the existing `paperclip-492823`)
- A billing-account grant (`paperclip-492823` already has billing
  attached via `01BCB7-61A725-D6A2B5`)
- A folder under the org (we don't need org-level permissions)
- An Anthropic API key (Vertex Claude uses the service account)
- An OpenAI API key (Codex agents are out of scope for v1)
- An email provider, SMTP credentials, SendGrid/SES/Resend account
  (Paperclip uses URL-based invitations)
- An external CDN, WAF, or load balancer service
- A separate database administrator — Paperclip runs Drizzle migrations
  itself on container boot

---

## 1. Verify project access and one-time prerequisites

This step is required once per fresh laptop / new operator. It does
not modify any GCP state.

### 1a. Confirm authentication and project context

```bash
gcloud auth list                           # active account = victor@greeteat.com (or your operator)
gcloud config set project paperclip-492823
gcloud projects describe paperclip-492823 \
  --format="value(projectId,parent.id,lifecycleState)"
```

Expected: project ID `paperclip-492823`, parent `768469506142`,
lifecycle `ACTIVE`.

### 1b. Verify Vertex AI Claude is reachable from the project

This is a definitive end-to-end test that the LLM provider works. If
it returns `HTTP 200`, the deployment can proceed.

```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)
curl -sS -w "\nHTTP_STATUS=%{http_code}\n" -X POST \
  "https://aiplatform.googleapis.com/v1/projects/paperclip-492823/locations/global/publishers/anthropic/models/claude-sonnet-4-6:rawPredict" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "anthropic_version": "vertex-2023-10-16",
    "messages": [{"role": "user", "content": "Reply with exactly: ok"}],
    "max_tokens": 10
  }'
```

Expected: `HTTP_STATUS=200` and a Claude response containing `"ok"`.
If you get `HTTP 404` with "Publisher Model … was not found", Claude
access is not enabled in Model Garden — go to
https://console.cloud.google.com/vertex-ai/model-garden?project=paperclip-492823,
filter by Anthropic, find the Claude Sonnet 4.6 card, and click
**Enable**.

### 1c. Bootstrap the Terraform state bucket (one-time)

A GCS bucket holds Terraform state with object versioning enabled.
This is created out-of-band before the first apply because Terraform
itself needs a state location.

Bucket name is `paperclip-492823-tf-state` — project-prefixed because
GCS bucket names are globally unique across all GCP customers, and
`paperclip-tf-state` was already taken by another tenant.

```bash
gcloud storage buckets create gs://paperclip-492823-tf-state \
  --project=paperclip-492823 \
  --location=us-central1 \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update gs://paperclip-492823-tf-state \
  --versioning
```

### 1d. The persistent state bucket (created by Terraform)

A second GCS bucket, `paperclip-492823-state`, serves as the GCS FUSE mount
at `/paperclip` inside Cloud Run. This is where Paperclip stores agent
instructions, PARA memory, workspaces, and `config.json`.

**No operator action needed here** — this bucket is created automatically by
Terraform (`module.storage`) during the first apply. It is documented here so
operators know it exists and understand its purpose.

---

## 2. Bootstrap secrets

Two one-shot scripts. They are idempotent in the sense that they refuse
to overwrite an existing secret (which would create a new version with
unknown content). To rotate, use the dedicated rotation procedure
(future Followup).

### 2a. Master encryption key

```bash
./infra/scripts/bootstrap-master-key.sh
```

This script:

1. Generates 32 bytes of randomness with `openssl rand -base64 32`
2. Creates the `paperclip-master-key` secret in Secret Manager
3. Adds the generated value as the first version
4. **Never writes the value to disk**

If the secret already exists, the script aborts with a warning.

### 2b. GCS HMAC interop credentials

```bash
./infra/scripts/bootstrap-gcs-hmac.sh
```

This script:

1. Creates a service account `paperclip-storage-sa` (if missing)
2. Generates an HMAC key for that service account
3. Stores `paperclip-s3-access-key-id` and
   `paperclip-s3-secret-access-key` in Secret Manager
4. Grants the service account `roles/storage.objectUser` only on the
   environment's bucket (created by Terraform in step 4)

**Note**: there is **no LLM API key bootstrap step**. Vertex Claude
uses the Cloud Run service account (`paperclip-runtime-sa`, granted
`roles/aiplatform.user` by Terraform). **Verified end-to-end on
2026-04-10**: Paperclip's `claude_local` adapter accepts the unset
state and the spawned Claude Code authenticates to Vertex via the
runtime IAM identity. **No `ANTHROPIC_API_KEY` secret is needed in
any form.**

---

## 3. Build the Paperclip image (first time)

Push a manual build of the pinned Paperclip release to Artifact
Registry. Subsequent builds run automatically in CI on PR merge.

```bash
# Triggered from GitHub Actions:
gh workflow run build-image.yml \
  --ref main \
  -f paperclip_version=v0.42.0
```

Once CI completes, capture the resulting image digest and write it to
`infra/envs/prod/versions.tfvars`:

```hcl
paperclip_version      = "v0.42.0"
paperclip_image_digest = "sha256:<digest>"
```

Commit and push the file. The CI's `terraform-plan.yml` workflow will
post the planned diff as a PR comment.

---

## 4. First Terraform apply

```bash
./infra/scripts/deploy.sh
```

The script (per `contracts/deploy-cli.md`):

1. Preflight: refuses if anything is uncommitted, the digest doesn't
   exist, env is missing, `CLOUDSDK_CORE_PROJECT` is not
   `paperclip-492823`, etc.
2. `terraform plan` — review the diff. First-deploy will create a few
   dozen resources.
3. Confirm — type `yes` to apply (or use `--auto-approve` in CI). For
   the production single-env you'll be asked to type `paperclip-492823`.
4. `terraform apply` — provisions:
   - Enables Paperclip-required APIs (run, sql, compute, secret, dns,
     vpcaccess, iam, iamcredentials, aiplatform if not already on)
   - `paperclip-vpc`, `paperclip-subnet`, `paperclip-connector`
   - `paperclip-pg` Cloud SQL instance (~15–25 minutes)
   - `paperclip-492823-uploads` GCS bucket
   - `paperclip-492823-state` GCS bucket (persistent `/paperclip` state via GCS FUSE mount)
   - Secret Manager IAM bindings (the secrets from step 2 must already
     exist)
   - `paperclip` Artifact Registry repository and IAM
   - `paperclip-runtime-sa` service account with the narrow IAM grants
   - `paperclip-github` Workload Identity Federation pool + provider
   - `paperclip` Cloud Run service (digest-pinned)
   - `paperclipai-doctor` Cloud Run Job
   - `paperclip-greeteat-zone` Cloud DNS zone
   - Cloud Run domain mapping → Cloud DNS records
   - `paperclipai-doctor-daily` Cloud Scheduler trigger
   - `paperclip-app-logs` and `paperclip-audit-logs` log buckets
   - Log Router sink filtering `service=paperclip event=auth`
   - Monitoring alerts and Uptime Check
5. Doctor gate — runs `paperclipai doctor` as a Cloud Run Job; deploy
   fails and rolls back if doctor fails
6. Smoke test — exercises US1 (operator sign-in landing) and US3
   (agent auth) against the new revision URL
7. Reports the new revision name, public URL, doctor result, and smoke
   result

---

## 5. Point DNS at Cloud Run

If you used a subdomain you fully control via Cloud DNS, Terraform
already wrote the records. Verify:

```bash
dig +short paperclip.greeteat.example
```

If you delegate the apex from a registrar outside Google, add the
NS records for the Cloud DNS zone at your registrar (Terraform output
`name_servers` shows you which to use).

Wait for the Google-managed cert to validate (typically 5–15 minutes
the first time). Cloud Run domain mapping status will move from
`PENDING` to `READY`.

---

## 6. Bootstrap the first board operator

**This is the trickiest step in the whole deploy.** Paperclip's
`bootstrap-ceo` invite does NOT create a user account — it promotes
an *already-signed-in* user to `instance_admin`. So you have a
chicken-and-egg with `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true`: the
deployment ships with sign-up disabled (per the GHSA-68qg-g8mg-6pr7
mitigation), but you need to sign up at least once to create the
account that will then claim the bootstrap invite.

**The canonical bootstrap dance is five steps and you must do them in
this exact order.** Skipping the temporary flip back at the end leaves
your deployment exposed to the GHSA RCE chain.

### Step 1 — Mint the bootstrap invite via Cloud Run Job

```bash
gcloud run jobs execute paperclipai-bootstrap-ceo \
  --region=us-central1 \
  --project=paperclip-492823 \
  --wait
```

The job (defined in `infra/modules/jobs/`) runs a wrapper script
(`bootstrap-ceo-wrapper.sh.tftpl`) that:
1. Materializes a minimal Paperclip `config.json` at
   `/paperclip/instances/default/config.json` — required because the
   `paperclipai auth bootstrap-ceo` CLI bails immediately if this file
   is absent. The CLI was designed for developer-laptop usage where
   `~/.paperclip` persists across runs; Cloud Run Jobs start with empty
   filesystems, so we have to create it inline. The file's database/auth
   values are placeholders — actual values come from env vars
2. Execs the CLI: `node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts auth bootstrap-ceo --base-url <PUBLIC_URL>`

After the job completes, capture the one-time invite URL from the
execution log:

```bash
EXEC=$(gcloud run jobs executions list \
  --job=paperclipai-bootstrap-ceo \
  --region=us-central1 --project=paperclip-492823 \
  --limit=1 --format='value(metadata.name)')

gcloud logging read "resource.type=cloud_run_job AND \
  resource.labels.job_name=paperclipai-bootstrap-ceo AND \
  labels.\"run.googleapis.com/execution_name\"=$EXEC" \
  --project=paperclip-492823 --limit=20 --freshness=10m \
  --format='value(textPayload)' | grep "Invite URL"
```

The URL looks like:

    https://paperclip-280667224791.us-central1.run.app/invite/pcp_bootstrap_<48-hex>

**Store the URL in your password manager.** It expires in 72 hours
(the default `--expires-hours` for the CLI). If you don't claim it in
time, run the job again to mint a fresh one (the CLI revokes any
unclaimed invites on each run).

### Step 2 — TEMPORARILY enable sign-up

The Terraform-managed `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` blocks the
sign-up endpoint. Flip it to `false` via `gcloud` for the bootstrap
window only:

```bash
gcloud run services update paperclip \
  --region=us-central1 \
  --project=paperclip-492823 \
  --update-env-vars=PAPERCLIP_AUTH_DISABLE_SIGN_UP=false
```

Cloud Run rolls a new revision in ~30-60 seconds and serves 100% of
traffic from it. **DO NOT touch `infra/modules/compute/main.tf` for
this step** — keep the Terraform state's source-of-truth value at
`true` so step 5 just reverts the gcloud override naturally.

> **Vulnerability window starts now.** During this window, anyone who
> knows your Cloud Run URL can sign up an account and execute the
> GHSA-68qg-g8mg-6pr7 RCE chain. The mitigation is that the URL is
> not yet published anywhere — you're the only one who knows it.
> Don't paste it into chat/email/social media. Move fast through
> steps 3-5 and re-lock.

### Step 3 — Create the seed operator account

1. Open the invite URL from step 1 in a private/incognito browser
   window. **Hard-refresh** (Cmd+Shift+R / Ctrl+Shift+R) if you
   already had the page open before step 2 — the frontend needs to
   reload to see the new server state
2. Click the sign-up link (or the "create account" CTA on the invite
   landing page). The form posts to `POST /api/auth/sign-up/email`
   with `{name, email, password}`
3. Better Auth creates the user and sets a session cookie
   automatically — you should be signed in immediately

### Step 4 — Accept the bootstrap invite

While still on the invite page (signed in), click **"Accept bootstrap
invite"**. The frontend POSTs to
`/api/invites/<token>/accept`, and the server runs:

```ts
if (invite.inviteType === "bootstrap_ceo") {
  // ...require authenticated user...
  if (!await access.isInstanceAdmin(req.actor.userId)) {
    await access.promoteInstanceAdmin(req.actor.userId);
  }
}
```

A 202 response means you're now `instance_admin` in the database.
Confirm by reaching the dashboard — if you can configure agents and
see settings, the promotion succeeded.

### Step 5 — Re-lock sign-up (CRITICAL)

The Terraform-managed value of `PAPERCLIP_AUTH_DISABLE_SIGN_UP` is
still `true`, so a plain `terraform apply` reverts the gcloud override
from step 2:

```bash
cd infra/envs/prod
terraform apply
```

Plan should show one in-place change to the Cloud Run service env
vars (flipping the variable back to `true`). Apply it.

**Verify the lockdown** with a smoke test from a separate terminal:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d '{"email":"attacker@evil.com","password":"x","name":"x"}' \
  https://paperclip-280667224791.us-central1.run.app/api/auth/sign-up/email \
  -w "\nHTTP %{http_code}\n"
```

Expected response:

```json
{"code":"EMAIL_AND_PASSWORD_SIGN_UP_IS_NOT_ENABLED","message":"Email and password sign up is not enabled"}
HTTP 400
```

If you see a 200, the lockdown didn't take — check the live env var
with `curl ... | python3 -c "import json,sys; ..."` and re-run
`terraform apply` until it's back to `"true"`.

The vulnerability window is now closed. Subsequent operator accounts
must come through the in-app invite flow (an existing admin generates
an invite from the settings page; the invitee claims it via a signed
URL — that flow works regardless of `disableSignUp` because Paperclip
uses a different code path for in-app invites).

### Why we can't skip the dance

We tried to ship with `disableSignUp=true` from day 0, hoping the
`bootstrap-ceo` invite was self-contained. It isn't. Specifically:

- **`POST /api/invites/<token>/accept` for `bootstrap_ceo` requires
  `req.actor.type === "board"`** (i.e. an authenticated session). It
  promotes the *signed-in user* to admin; it doesn't create a user.
- **`POST /api/auth/sign-up/email` is gated by Better Auth's
  `disableSignUp` flag**. With sign-up disabled, you can't get a user
  to be signed in as.
- The two endpoints don't share any "bootstrap bypass" code path.

This is consistent with how Paperclip is designed to be installed:
operators run `paperclipai onboard` → set up local instance → sign up
the first user → run `bootstrap-ceo` → accept invite → THEN flip
`disableSignUp` if going public. We have to compress the same dance
into a Cloud Run Job + 2 gcloud commands.

---

## 7. Verify the spec's P1 acceptance scenarios

### US1 — operator sign-in works

1. From an unprivileged network (no VPN), navigate to your public
   URL (e.g. `https://paperclip.greeteat.example`)
2. You should see the Better Auth sign-in flow
3. Sign in with the seed operator credentials
4. You should land on the dashboard within ~10 seconds (SC-002)

### US2 — invitation-only registration works

1. From the dashboard, navigate to settings → operators → invite
2. Generate an invitation; the URL should be auto-copied to clipboard
3. Open a private browser window (or sign out)
4. Navigate to the invitation URL — you should see the claim flow
5. Without an invitation URL, attempt to sign up — every visible flow
   should be refused with "registration is by invitation only"

### US3 — agent auth works (and Vertex Claude works end-to-end)

1. From the dashboard, create a test company and a test agent
2. Generate an agent API key (or run the agent runtime which will
   receive a JWT during heartbeat)
3. From a separate terminal, hit the public API:
   ```bash
   curl -H "Authorization: Bearer $AGENT_API_KEY" \
     https://paperclip.greeteat.example/api/agents/me
   ```
4. The response should return the agent's identity, scoped to its
   company
5. Trigger the test agent's first heartbeat (via the dashboard's
   "Wake Now" button or its scheduled cadence). The agent should
   spawn Claude Code, which authenticates to Vertex via the
   `paperclip-runtime-sa` identity (no `ANTHROPIC_API_KEY` needed),
   and returns work to Paperclip. The agent's run log will show
   message IDs with the `msg_vrtx_*` prefix — that's the Vertex
   marker, confirming the LLM call went through Vertex AI Claude
   Sonnet 4.6 (the same path verified end-to-end locally on
   2026-04-10).

If all three pass, the deployment is verified.

---

## 8. Day-2 operations

### Deploying a Paperclip upgrade

1. Bump `paperclip_version` in `infra/envs/prod/versions.tfvars`
2. Open a PR. CI builds the new image and posts the digest as a comment.
3. Update `paperclip_image_digest` in the same PR with the digest from
   CI's output.
4. Merge the PR. The `deploy.yml` workflow runs `deploy.sh`
   automatically (or manually triggered).
5. The deploy gates (doctor + smoke) catch regressions. If either
   fails, automatic rollback.

### Rolling back

```bash
./infra/scripts/rollback.sh --to-previous --reason "5xx spike after 14:32 deploy"
```

See `contracts/rollback-cli.md` for the full contract. SC-005 budgets
30 minutes from invocation to all P1 scenarios passing on the
rolled-back revision. **`--reason` is always required** — single env
is treated as production, every rollback is audited.

### Inviting a new board operator

1. From the dashboard, settings → operators → invite
2. Copy the invitation URL (auto-copied to clipboard)
3. Share the URL out-of-band through any channel you trust (Slack,
   Signal, in person)
4. The invitee opens the URL within 10 minutes and completes sign-up

### Daily doctor check

`paperclipai-doctor-daily` runs once per day via Cloud Scheduler in
`us-central1`. If it fails, the alerting policy fires and pages the
on-call operator. To run it manually:

```bash
./infra/scripts/doctor.sh
```

### Inspecting auth events

```bash
gcloud logging read \
  'logName="projects/paperclip-492823/logs/paperclip.audit"' \
  --project=paperclip-492823 \
  --limit=50 \
  --format=json
```

Auth events are retained for 90 days in the `paperclip-audit-logs` log
bucket (FR-020).

---

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| `deploy.sh` exits 2 immediately | Preflight failed; uncommitted changes, missing env var, wrong project | Script stderr |
| `terraform apply` fails on Cloud SQL creation | Quota or network conflict (e.g. Private Services Access not configured) | GCP console → Cloud SQL → events; `gcloud sql operations list` |
| `terraform apply` succeeds but doctor fails | Config drift between image and resolved secrets | Cloud Run Jobs → paperclipai-doctor → execution → logs |
| Public URL returns Cloud Run's default 404 | Domain mapping not READY yet | `gcloud run domain-mappings describe …` |
| Public URL returns 502/503 | Cloud Run service has zero ready instances | Cloud Run service → revisions → logs |
| Sign-in succeeds but the dashboard is empty | Database connection failed at runtime | Cloud Run service logs for `DATABASE_URL` errors |
| Uploads fail with auth errors | GCS HMAC credential mismatch | Re-run `bootstrap-gcs-hmac.sh` and verify Secret Manager versions |
| Daily doctor fails | Drift in deployment-mode config or missing secret | Cloud Run Jobs → execution logs |
| Claude Code fails with "401" or "PERMISSION_DENIED on aiplatform.endpoints.predict" | `paperclip-runtime-sa` missing `roles/aiplatform.user`, OR Vertex env vars not set on the Cloud Run service | Verify with `gcloud projects get-iam-policy paperclip-492823 --flatten=bindings[].members --filter=bindings.members:paperclip-runtime-sa@*`; verify `CLAUDE_CODE_USE_VERTEX`, `CLOUD_ML_REGION`, `ANTHROPIC_VERTEX_PROJECT_ID` in the Cloud Run service env |
| Vertex returns 404 "publisher model not found" | Claude not enabled in Model Garden | https://console.cloud.google.com/vertex-ai/model-garden?project=paperclip-492823 — enable Claude Sonnet 4.6 |

---

## Things that bit us during the first deploy

This section is the operator's "I wish I had known" log from the
2026-04-11 first deploy. Each entry is a real failure that cost
debug time, with the symptom you'll see and the fix.

### `terraform apply` errors

**`Error: Request had invalid authentication credentials. Expected
OAuth 2 access token …` mid-apply**

Your Workspace's reauth policy expired your ADC token while
Terraform was waiting on a long-running resource (Cloud SQL: ~15-25
min, Service Networking Connection: ~5 min). This is GCP's RAPT
("reauth-related access token") expiration and it bites every long
apply on a Workspace-managed Google account.

**Fix**: don't run `terraform apply` for Phase 3 from your laptop's
gcloud ADC. Use one of:
1. **Cloud Shell** (`console.cloud.google.com` → top-right shell icon)
   — its auth is sticky for the session, no RAPT enforcement
2. **Service account key file**: `gcloud iam service-accounts keys
   create paperclip-tf.json --iam-account=paperclip-github-actions@...`
   then `export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/paperclip-tf.json`
   before running terraform. Delete the key file when done
3. **GitHub Actions** (Phase 6 `deploy.yml`) — same auth path as
   `build-image.yml`, no RAPT issues

If you do hit the failure mid-apply, the recovery is:
1. `gcloud auth application-default login` to refresh
2. `terraform force-unlock <id>` to clear the stale GCS state lock
3. `terraform state push errored.tfstate` to sync state with reality
4. `terraform apply` to resume from where it died

**`Error: cannot destroy service without setting
deletion_protection=false`**

Google provider 6.x defaults
`google_cloud_run_v2_service.deletion_protection` to `true`. This is
a client-side check by the provider — not an API enforcement — so
the **fix is in `infra/modules/compute/main.tf` (already set to
`false`)**, but if Terraform is mid-recovery from a failed apply
where the resource is in state with `true`, the destroy step still
fails. Recovery:

1. Delete the service via REST API directly (the GCP API has no
   such enforcement):
   ```bash
   curl -X DELETE -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     "https://run.googleapis.com/v2/projects/paperclip-492823/locations/us-central1/services/paperclip"
   ```
2. Remove from state: `terraform state rm
   module.compute.google_cloud_run_v2_service.paperclip`
3. Re-run `terraform apply` — Terraform creates fresh

### Cloud Run service won't start

**`PostgresError: pg_hba.conf rejects connection for host
"10.8.0.x", user "paperclip", database "paperclip", no encryption`**

The `postgres.js` npm client (which Paperclip uses) does NOT
auto-negotiate TLS on private-IP connections; Cloud SQL with
`ssl_mode = "ENCRYPTED_ONLY"` rejects the auth handshake.

**Fix**: the `database` module's connection string includes
`?sslmode=require`. Already correct in
`infra/modules/database/main.tf`; if you're seeing this error, you're
on a stale revision — `terraform apply` to roll a new one.

**`The user-provided container failed to start and listen on the
port defined provided by the PORT=3100 environment variable`**

Cloud Run gave up waiting for the container to bind port 3100.
Causes seen so far:
- DATABASE_URL connection failure (see above)
- Missing required env var (BETTER_AUTH_SECRET, MASTER_KEY)
- Vertex env var typos
- The image's CMD was overridden incorrectly (especially in
  Cloud Run Jobs)

**Where to look**: Cloud Run service → revisions → click the failing
revision → Logs tab. Or:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="paperclip"' \
  --project=paperclip-492823 --limit=100 --freshness=10m \
  --format='value(timestamp,textPayload,jsonPayload.message)'
```

### Bootstrap-ceo Cloud Run Job failures

**`Application failed to start: The container may have exited
abnormally`** or **`Application exec likely failed`**

The job's `command` was overriding the upstream Docker ENTRYPOINT
(`docker-entrypoint.sh`) with a non-existent binary.

**Fix**: in `infra/modules/jobs/main.tf`, leave `command` UNSET so
the entrypoint stays as `docker-entrypoint.sh` (which does
`exec gosu node "$@"`). Put your actual command in `args` instead.

**`No config found at /paperclip/instances/default/config.json. Run
paperclip onboard first.`**

The `paperclipai auth bootstrap-ceo` CLI requires a config file
that doesn't exist in a Cloud Run Job's empty filesystem.

**Fix**: the wrapper script
`infra/modules/jobs/bootstrap-ceo-wrapper.sh.tftpl` materializes a
minimal `config.json` before exec'ing the CLI. If you're seeing this
error, the wrapper isn't running — re-apply Terraform and re-execute
the job.

### Sign-up returns 400 / 401 / can't accept invite

**`{"code":"EMAIL_AND_PASSWORD_SIGN_UP_IS_NOT_ENABLED","message":"Email
and password sign up is not enabled"}`**

`PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` is correct for steady state but
blocks the first user creation. **You're missing the bootstrap dance
(section 6 above).** Flip `disableSignUp=false` via gcloud, sign up,
accept invite, then re-flip via `terraform apply`.

**Sign-in returns 401 immediately after sign-up**

Better Auth couldn't find the user. Either:
- Your sign-up never persisted (check Cloud Run logs for
  `POST /api/auth/sign-up/email` — looking for 200, not 400)
- You're hitting an old revision via cached state — hard-refresh
  the browser (Cmd+Shift+R)

### Image build / Trivy failures

**`Unable to resolve action aquasecurity/trivy-action@<version>`**

The pinned version doesn't exist on the action's repo. Check
`https://github.com/aquasecurity/trivy-action/releases` for the
current latest stable and update `.github/workflows/build-image.yml`.

**`sha256sum: WARNING: 1 computed checksum did NOT match` in the
Docker build**

GitHub rotated the `cli.github.com` archive keyring SHA, and
upstream Paperclip's Dockerfile pins the old one. The
`build-image.yml` workflow has a "Patch upstream Dockerfile" step
that fetches the current SHA fresh and seds it into the cloned
Dockerfile — if it stops working, check that step.

**Trivy fails on dozens of HIGH/CRITICAL CVEs in upstream-bundled
tooling**

Some of these are real (the Paperclip RCE GHSA) and some are noise
(golang stdlib in compiled binaries that Paperclip never invokes
at runtime). Per-CVE reachability analysis lives in `.trivyignore`
at the repo root. If a *new* CVE shows up that's not in the
allowlist, triage it (is it reachable in Paperclip's runtime path?)
and either fix upstream or add to the allowlist with documented
justification. Re-review the allowlist on every Paperclip version
bump.

### Agents fail or fall back to curl when calling web_search

**Symptom**: agent run logs show `WebFetch` / `WebSearch` tool calls
returning errors like:

    API Error: 400
    Organization Policy constraint
    constraints/vertexai.allowedPartnerModelFeatures violated for
    `projects/280667224791` attempting to use a disallowed feature
    web_search for Partner model claude-opus-4-6.

The greeteat.com Cloud Org enforces a `denyAll: true` policy on the
`vertexai.allowedPartnerModelFeatures` constraint by default, which
blocks Claude's built-in `web_search` (and presumably other partner
model features). Agents detect the failure and fall back to spawning
`curl` to fetch web pages, which works but is less efficient — Claude
has to parse raw HTML instead of getting ranked, summarized results.

**Fix**: set a project-level override that allows `web_search` for
the specific Anthropic models you've enabled in Model Garden.

Required role: `roles/orgpolicy.policyAdmin` granted at the
**organization level** (`organizations/<org-id>`). Project Owner does
NOT include this — you have to be either:

- An actual Cloud IAM Organization Administrator, OR
- A Workspace Super Admin who self-grants the `Google Cloud Platform
  admin` Workspace pre-built role (which then maps to Cloud IAM Org
  Admin), OR
- Granted `roles/orgpolicy.policyAdmin` at the org level by someone
  else who has it

Once you have the role, the override is one command. Save this YAML
to a tempfile and apply:

```yaml
# /tmp/web-search-policy.yaml
name: projects/paperclip-492823/policies/vertexai.allowedPartnerModelFeatures
spec:
  rules:
  - values:
      allowedValues:
      - publishers/anthropic/models/claude-opus-4-6:web_search
      - publishers/anthropic/models/claude-sonnet-4-6:web_search
      - publishers/anthropic/models/claude-haiku-4-5:web_search
```

```bash
# enable the API on the project (one-time, idempotent)
gcloud services enable orgpolicy.googleapis.com \
  --project=paperclip-492823

# apply the override
gcloud org-policies set-policy /tmp/web-search-policy.yaml

# verify the effective policy reflects the override
gcloud org-policies describe \
  constraints/vertexai.allowedPartnerModelFeatures \
  --project=paperclip-492823 \
  --effective
```

The effective policy should now show your three `is:publishers/...`
allowedValues instead of `denyAll: true`. Vertex picks up the change
on the next request — no Cloud Run redeploy needed.

Add new model variants (e.g., when Claude 4.7 ships) by editing the
YAML and re-running `set-policy`.

### "Model not available on your vertex deployment" with confusing fallback suggestions

**Symptom**: from inside a Cloud Run container or via `curl` to Vertex,
Claude Code reports:

    The model claude-sonnet-4-5 is not available on your vertex
    deployment. Try --model to switch to claude-sonnet-4@20250514,
    or ask your admin to enable this model.

**This error is misleading.** It suggests the named model isn't
enabled, but the actual cause is almost always one of:

1. **Wrong model identifier**: e.g. you typed `claude-sonnet-4-5` but
   the only Sonnet variant subscribed in your project's Model Garden
   is `claude-sonnet-4-6` (or vice versa). Vertex Model Garden
   enablement is **per model variant** — Sonnet 4.5 and Sonnet 4.6
   are separate subscriptions, and the dashboard / `claude --model`
   short names may not match the actual subscribed variants
   one-to-one.
2. **Wrong region**: Anthropic models on Vertex are only enabled in
   specific regions (typically `us-east5`, `europe-west1`, plus
   `global`). If your `CLOUD_ML_REGION` env var or the per-call
   region doesn't match where the model was enabled, you get this
   error too.
3. **Model not enabled at all**: the rare case where the operator
   genuinely forgot to click "ENABLE" in the Cloud Console.

**Diagnostic recipe**: spawn a one-off Cloud Run Job using the same
image, runtime SA, and VPC connector, with a CMD that loops over
candidate model identifiers and tries `claude --print --model
$MODEL`. The ones that respond with "Hi! How can I help you today?"
are the ones actually enabled. Example diagnostic JSON spec lives in
`infra/scripts/` (TODO: codify as a script — for now see the
2026-04-11 deploy log in research.md Decision 18+).

The diagnostic is often more useful than the Cloud Console because
it tests with the exact identity, network path, and env that the
real agent uses.

### Diagnostic Cloud Run Jobs are an underused tool

When something goes wrong with a Cloud Run service and you need to
test "what happens when this image runs as this SA on this VPC", the
fastest path is **NOT** to add print statements and rebuild the
image — it's to spin up a **one-off Cloud Run Job** using the same
image and a CMD that runs your diagnostic shell script. Create →
execute → read logs → delete, all via REST API or `gcloud`.

This pattern saved hours during the first deploy when we had to
verify Claude Code was reachable, models were enabled, and the
runtime SA could call Vertex. The job costs essentially nothing
(charged by the second of compute), runs in ~60 seconds, and gives
you the actual answer instead of inferred guesses.

**Skeleton** (POST to Cloud Run Jobs v2 API with auth header
`Bearer $(gcloud auth print-access-token)`):

```json
{
  "labels": { "service": "paperclip-diagnostic" },
  "template": {
    "template": {
      "serviceAccount": "paperclip-runtime-sa@paperclip-492823.iam.gserviceaccount.com",
      "vpcAccess": {
        "connector": "projects/paperclip-492823/locations/us-central1/connectors/paperclip-connector",
        "egress": "PRIVATE_RANGES_ONLY"
      },
      "maxRetries": 0,
      "timeout": "300s",
      "containers": [{
        "image": "us-central1-docker.pkg.dev/paperclip-492823/paperclip/paperclip@sha256:<digest>",
        "command": ["sh"],
        "args": ["-c", "<your shell script here>"],
        "env": [
          {"name": "CLAUDE_CODE_USE_VERTEX", "value": "1"},
          {"name": "CLOUD_ML_REGION", "value": "global"},
          {"name": "ANTHROPIC_VERTEX_PROJECT_ID", "value": "paperclip-492823"},
          {"name": "HOME", "value": "/paperclip"}
        ]
      }]
    }
  }
}
```

POST to:

    https://run.googleapis.com/v2/projects/paperclip-492823/locations/us-central1/jobs?jobId=paperclip-diagnostic

Then `gcloud run jobs execute paperclip-diagnostic --region=us-central1
--project=paperclip-492823 --wait`, read logs via `gcloud logging read
'resource.type="cloud_run_job" AND
resource.labels.job_name="paperclip-diagnostic"'`, then DELETE the job
via REST API. Total turnaround: ~2 minutes.
