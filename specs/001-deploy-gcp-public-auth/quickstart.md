# Quickstart: First Deploy of GreetEat Paperclip on GCP

**Audience**: A platform operator deploying GreetEat Paperclip into the
shared `greeteat-staging` GCP project for the first time, OR after a
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
  `greeteat-staging` (Victor confirmed on 2026-04-10)
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

- A new GCP project (we use the existing `greeteat-staging`)
- A billing-account grant (`greeteat-staging` already has billing
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
gcloud config set project greeteat-staging
gcloud projects describe greeteat-staging \
  --format="value(projectId,parent.id,lifecycleState)"
```

Expected: project ID `greeteat-staging`, parent `768469506142`,
lifecycle `ACTIVE`.

### 1b. Refresh Application Default Credentials

ADC is needed for Terraform's `google` provider when applying locally.
This is a known cleanup item — without it, Terraform will fail with
`serviceusage.services.use` permission errors.

```bash
gcloud auth application-default login
# (the above also auto-attaches the quota project on success)
```

> **Local-dev caveat**: `victor@greeteat.com` Workspace policies enforce
> aggressive RAPT (reauth proof token) expiry on `cloud-platform` scope —
> ADC tokens stop working after ~10–15 minutes of idle and you have to
> re-run the login. This makes sustained local testing painful.
>
> **Recommended local-dev fix** (one-time): create a dedicated
> `paperclip-local-dev` service account in `greeteat-staging` with
> `roles/aiplatform.user` only, generate a JSON key, store it locally
> (never commit), and point at it instead of user ADC:
>
> ```bash
> gcloud iam service-accounts create paperclip-local-dev \
>   --display-name="Paperclip local dev (Vertex Claude)" \
>   --project=greeteat-staging
>
> gcloud projects add-iam-policy-binding greeteat-staging \
>   --member="serviceAccount:paperclip-local-dev@greeteat-staging.iam.gserviceaccount.com" \
>   --role="roles/aiplatform.user"
>
> mkdir -p ~/.config/gcloud/keys
> gcloud iam service-accounts keys create \
>   ~/.config/gcloud/keys/paperclip-local-dev.json \
>   --iam-account=paperclip-local-dev@greeteat-staging.iam.gserviceaccount.com
>
> export GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/keys/paperclip-local-dev.json
> ```
>
> Service account tokens auto-refresh, no RAPT, no MFA prompts. **Production
> Cloud Run is unaffected** — it uses metadata-server tokens for
> `paperclip-runtime-sa`, not this key.

### 1c. Verify Vertex AI Claude is reachable from the project

This is a definitive end-to-end test that the LLM provider works. If
it returns `HTTP 200`, the deployment can proceed.

```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)
curl -sS -w "\nHTTP_STATUS=%{http_code}\n" -X POST \
  "https://aiplatform.googleapis.com/v1/projects/greeteat-staging/locations/global/publishers/anthropic/models/claude-sonnet-4-6:rawPredict" \
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
https://console.cloud.google.com/vertex-ai/model-garden?project=greeteat-staging,
filter by Anthropic, find the Claude Sonnet 4.6 card, and click
**Enable**.

### 1d. Bootstrap the Terraform state bucket (one-time)

A GCS bucket holds Terraform state with object versioning enabled.
This is created out-of-band before the first apply because Terraform
itself needs a state location.

```bash
gcloud storage buckets create gs://paperclip-tf-state \
  --project=greeteat-staging \
  --location=us-central1 \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update gs://paperclip-tf-state \
  --versioning
```

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
   `greeteat-staging`, etc.
2. `terraform plan` — review the diff. First-deploy will create a few
   dozen resources.
3. Confirm — type `yes` to apply (or use `--auto-approve` in CI). For
   the production single-env you'll be asked to type `greeteat-staging`.
4. `terraform apply` — provisions:
   - Enables Paperclip-required APIs (run, sql, compute, secret, dns,
     vpcaccess, iam, iamcredentials, aiplatform if not already on)
   - `paperclip-vpc`, `paperclip-subnet`, `paperclip-connector`
   - `paperclip-pg` Cloud SQL instance (~15–25 minutes)
   - `greeteat-paperclip-uploads-prod` GCS bucket
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

The first operator account cannot exist before the deployment is up;
it has to be created against the running Paperclip instance. Paperclip's
documented bootstrap path uses a one-time "claim URL" generated when
transitioning from `local_trusted` to `authenticated` mode. In a clean
public-mode deployment, the bootstrap path runs as a Cloud Run Job:

```bash
gcloud run jobs execute paperclipai-bootstrap-admin \
  --region=us-central1 \
  --update-env-vars=BOOTSTRAP_OPERATOR_IDENTIFIER="$YOUR_IDENTIFIER" \
  --wait
```

The job (defined in `infra/modules/jobs/`) creates the seed operator
and prints a one-time claim URL. **Store the URL in your password
manager** — it expires within 10 minutes.

> If `paperclipai` does not yet ship a documented non-interactive
> bootstrap-admin command, the workaround is to run the same job in
> interactive mode via `gcloud run jobs execute --interactive`
> (followup: wrap this in a script once Paperclip's command is
> stable).

Open the URL in a browser. Complete sign-up. You now hold the first
board-operator account.

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
  'logName="projects/greeteat-staging/logs/paperclip.audit"' \
  --project=greeteat-staging \
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
| Claude Code fails with "401" or "PERMISSION_DENIED on aiplatform.endpoints.predict" | `paperclip-runtime-sa` missing `roles/aiplatform.user`, OR Vertex env vars not set on the Cloud Run service | Verify with `gcloud projects get-iam-policy greeteat-staging --flatten=bindings[].members --filter=bindings.members:paperclip-runtime-sa@*`; verify `CLAUDE_CODE_USE_VERTEX`, `CLOUD_ML_REGION`, `ANTHROPIC_VERTEX_PROJECT_ID` in the Cloud Run service env |
| Vertex returns 404 "publisher model not found" | Claude not enabled in Model Garden | https://console.cloud.google.com/vertex-ai/model-garden?project=greeteat-staging — enable Claude Sonnet 4.6 |
| Firebase scheduled jobs start failing | **Almost certainly unrelated to Paperclip**, but verify the `firebase-schedule-*` Cloud Scheduler jobs are still healthy. Paperclip resources should not affect them. | Cloud Scheduler in `us-central1` |
