# Contract: `./scripts/rollback.sh`

**Implements**: User Story 5 (operator can roll back a bad deployment)
**Lives at**: `infra/scripts/rollback.sh`
**Invoked by**: human operator OR `deploy.sh` automatically on a failed doctor/smoke gate

Rolling back the GreetEat Paperclip deployment is a first-class
operation, not an emergency improvisation. This contract defines what
"rollback" means for this deployment.

## Synopsis

```text
./scripts/rollback.sh (--to-previous | --to-revision REV) --reason TEXT

(No ENVIRONMENT positional — single-environment deployment.)

--to-previous        Roll back to the immediately previous revision (the
                     one that held 100% of traffic before the most
                     recent promote).
--to-revision REV    Roll back to a specific Cloud Run revision name.
                     Must already exist in the service.
--reason TEXT        Free-text reason. Always required (the single env
                     IS production; every rollback is audited).
                     Recorded in the deploy log.
```

## Required environment

| Variable | Purpose |
|---|---|
| WIF assertion from GitHub Actions | Authentication via the `paperclip-github` WIF pool. CI-only path, same as `deploy.sh`. |
| `CLOUDSDK_CORE_PROJECT` | Target project. |
| `GREETEAT_DEPLOY_OPERATOR` | Operator identifier; required and audited. |

## Behavior

1. **Preflight** — refuse to run if:
   - `CLOUDSDK_CORE_PROJECT` is not `paperclip-492823`
   - the requested target revision does not exist in the service
   - `--to-previous` would resolve to the same revision currently
     serving 100% (nothing to roll back)
   - `--reason` is not set
2. **Determine target revision**:
   - `--to-previous`: read the Cloud Run service's revision history and
     pick the most recent one that previously held 100% of traffic.
   - `--to-revision REV`: use exactly REV.
3. **Shift traffic**:
   `gcloud run services update-traffic <service> --to-revisions REV=100
    --region=$REGION --project=$PROJECT`
   Cloud Run shifts traffic atomically; new requests land on the
   previous revision within seconds.
4. **Health check** — wait until the public Uptime Check reports the
   new (rolled-back) revision healthy, or until 5 minutes have passed.
5. **Doctor on rollback** — execute the doctor Cloud Run Job against
   the rolled-back service. Doctor MUST pass; if it does not, the
   rollback itself is suspect and the script exits with code 6
   (manual intervention required).
6. **Record** — write a structured deploy-log entry to Cloud Logging
   under `greeteat.deploy` with `event=rollback`, the from-revision,
   to-revision, operator identity, reason, and timing.
7. **Report** — print the previous and current revision names, the
   public URL, and the doctor result.

## Exit codes

| Exit code | Meaning |
|---|---|
| 0 | Rollback succeeded; service is at the target revision; doctor passes. |
| 1 | Generic failure. |
| 2 | Preflight failed (no target, no reason, etc.). |
| 4 | Traffic shift succeeded but doctor failed against the rolled-back revision — investigate. |
| 6 | Traffic shift itself failed; the service may be in an indeterminate state — manual intervention required. |

## What rollback does NOT do

- Does **not** roll back database schema changes. If the failed deploy
  applied a Drizzle migration that the previous revision is not
  compatible with, the rollback will fail at the doctor step. This is
  the schema-drift CI gate followup in `research.md` Decision 3 — until
  that gate exists, schema-affecting deploys must be coordinated by
  hand.
- Does **not** roll back Secret Manager values, Cloud SQL state, or GCS
  contents. State-changing operations are the operator's responsibility
  to manage at the data layer.
- Does **not** modify Terraform state directly. The Cloud Run revision
  is shifted via gcloud; Terraform will reconcile on the next apply.

## Recovery time objective

The script targets **< 30 minutes** from invocation to all P1
acceptance scenarios passing on the rolled-back revision (matches
SC-005). Most rollbacks complete in under 5 minutes; the budget exists
for the doctor + Uptime Check verification window.

## Constitution mapping

- **III. Reversible Deployments**: this script IS the reversible-deploy
  promise. Without it, principle III is theoretical.
- **V. Observability**: every rollback writes a deploy-log entry.
- **Operational Constraints**: requires `--reason` for production so
  the rollback is auditable.
