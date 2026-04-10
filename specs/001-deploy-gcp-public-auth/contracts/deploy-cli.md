# Contract: `./scripts/deploy.sh`

**Implements**: User Story 4 (operator deploys and updates the stack reproducibly)
**Lives at**: `infra/scripts/deploy.sh`
**Invoked by**: human operator from a workstation, OR `.github/workflows/deploy.yml`

This is the single documented entry point for deploying the GreetEat
Paperclip stack to GCP. It is the only thing FR-007 promises operators
will need to run.

## Synopsis

```text
./scripts/deploy.sh [--auto-approve]

(No ENVIRONMENT positional — single-environment deployment.)

--auto-approve       Skip the interactive Terraform apply confirmation.
                     Required in CI. Refused from a workstation unless
                     GREETEAT_DEPLOY_AUTOAPPROVE=1 is also set in the
                     environment.
```

The `--skip-doctor` and `--skip-smoke` flags from earlier drafts have been
removed entirely. The single environment is treated as production, and
neither gate is ever skippable.

## Required environment

The script REQUIRES the following to be set on the calling shell:

| Variable | Purpose |
|---|---|
| WIF assertion from GitHub Actions | Authentication to the target project via the project-scoped Workload Identity Federation pool `paperclip-github`. The script is intended to run from CI; running from a workstation is not a supported v1 path. |
| `CLOUDSDK_CORE_PROJECT` | Target GCP project ID. Must equal `paperclip-492823`. The script refuses to run against any other project. |
| `GREETEAT_DEPLOY_OPERATOR` | Identifier of the human triggering the deploy. Recorded in audit logs. Refuses to run if unset. |

## Behavior

1. **Preflight** — refuse to run if:
   - the working tree has uncommitted changes (FR-013)
   - the current branch is not `main`
   - any required env var is unset
   - `CLOUDSDK_CORE_PROJECT` is not `paperclip-492823`
   - the Paperclip image digest in `versions.tfvars` does not exist in
     Artifact Registry
   - `gcloud auth list` shows no active account in CI mode
2. **Plan** — `terraform -chdir=infra/envs/prod plan -out=plan.tfplan`.
   Output is preserved in `plan.tfplan` and printed to stdout.
3. **Confirm** — interactive prompt unless `--auto-approve`. The prompt
   requires the operator to type the project ID (`paperclip-492823`).
4. **Apply** — `terraform -chdir=infra/envs/prod apply plan.tfplan`.
   Captures the new Cloud Run revision name from the apply output.
5. **Doctor gate** — `gcloud run jobs execute paperclipai-doctor --wait
   --region=us-central1` against the same image and resolved secrets.
   If non-zero, the script invokes `./scripts/rollback.sh --to-previous
   --reason "doctor failed during deploy <revision>"` and exits non-zero
   with the doctor output attached.
6. **Smoke test** — runs the P1 smoke test against the new revision URL.
   The smoke test exercises US1 (operator sign-in landing) and US3
   (agent auth path), in headless mode where possible. If smoke fails,
   rollback as above.
7. **Promote** — the new revision receives 100% of traffic only after
   doctor and smoke pass. The script records the promoted revision in
   the project's deploy log (a Cloud Logging entry under
   `greeteat.deploy`).
8. **Report** — prints the new revision name, the public URL, the
   doctor result, and the smoke test result.

## Exit codes

| Exit code | Meaning |
|---|---|
| 0 | Deploy succeeded; service is at the new revision; doctor and smoke passed. |
| 1 | Generic failure (catch-all). |
| 2 | Preflight failed (uncommitted changes, missing env, missing image digest, etc.). |
| 3 | `terraform plan` or `apply` failed. |
| 4 | Doctor gate failed; rollback executed; service is back on the previous revision. |
| 5 | Smoke test failed; rollback executed; service is back on the previous revision. |
| 6 | Rollback itself failed — manual intervention required. |
| 10 | Aborted by operator at the confirmation prompt. |

## Side effects

- Writes `plan.tfplan` to the working directory.
- Writes a deploy-log entry to Cloud Logging under
  `logName=projects/<project>/logs/greeteat.deploy`, including operator
  identity, revision, exit code, and timing.
- Updates Terraform state in the project's GCS state bucket.
- Modifies Cloud Run, Cloud SQL, GCS, Secret Manager, Cloud DNS, and
  related resources only as described by the Terraform plan.

## Constitution mapping

- **I. Configuration as Code**: refuses to apply with uncommitted local
  changes; refuses to deploy a digest that didn't come from CI.
- **III. Reversible Deployments**: refuses to skip doctor or smoke for
  production; on failure, automatically calls `rollback.sh`.
- **IV. Secrets Discipline**: never echoes resolved secret values; only
  references Secret Manager entries by name.
- **V. Observability**: writes a structured deploy-log entry per run.

## Non-goals

- Does not bootstrap the GCP project. The project (`paperclip-492823`)
  is created manually before first deploy by an operator with org-level
  `roles/resourcemanager.projectCreator`. The one-time bootstrap
  consists of `bootstrap-master-key.sh`, `bootstrap-gcs-hmac.sh`, and
  a single `terraform apply` to enable APIs and create state — covered
  in `quickstart.md`.
- Does not rotate secrets.
- Does not promote between environments — there is only one environment
  in v1.
