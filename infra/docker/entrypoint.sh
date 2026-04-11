#!/usr/bin/env bash
# =============================================================================
# Paperclip Cloud Run entrypoint
# =============================================================================
# Runs as PID 1 inside the Cloud Run container. Validates required env vars,
# logs sanitised startup info, then `exec`s Paperclip's server process so it
# inherits PID 1 and receives SIGTERM cleanly during Cloud Run rollouts.
#
# Drizzle migrations run automatically on Paperclip's first boot per its
# architecture docs — we don't need to invoke them separately.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Required env-var validation
# -----------------------------------------------------------------------------
required_vars=(
  # Secret Manager-mounted (resolved by Cloud Run at task launch)
  PAPERCLIP_SECRETS_MASTER_KEY
  DATABASE_URL
  S3_ACCESS_KEY_ID
  S3_SECRET_ACCESS_KEY

  # Plain Cloud Run env (set in the task definition)
  HOST
  PAPERCLIP_DEPLOYMENT_MODE
  PAPERCLIP_PUBLIC_URL
  PAPERCLIP_SECRETS_STRICT_MODE
  S3_ENDPOINT
  S3_BUCKET

  # Vertex AI (Claude) — service account auth, no API key needed
  CLAUDE_CODE_USE_VERTEX
  CLOUD_ML_REGION
  ANTHROPIC_VERTEX_PROJECT_ID
)

missing=()
for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    missing+=("$v")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "ERROR: missing required environment variables:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if [ "$PAPERCLIP_DEPLOYMENT_MODE" != "public" ]; then
  echo "ERROR: PAPERCLIP_DEPLOYMENT_MODE must be 'public' (got '$PAPERCLIP_DEPLOYMENT_MODE')" >&2
  exit 1
fi

if [ "$CLAUDE_CODE_USE_VERTEX" != "1" ]; then
  echo "ERROR: CLAUDE_CODE_USE_VERTEX must be '1' (got '$CLAUDE_CODE_USE_VERTEX')" >&2
  exit 1
fi

# Confirm we are NOT carrying an Anthropic API key — Vertex Claude uses
# service account auth and no API key should be present in production.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "WARNING: ANTHROPIC_API_KEY is set. Vertex Claude does not need it." >&2
  echo "         If this is the documented stub for the Paperclip preflight," >&2
  echo "         ignore this warning. Otherwise consider removing it." >&2
fi

# -----------------------------------------------------------------------------
# Sanitised startup log line
# -----------------------------------------------------------------------------
# Mask the password portion of DATABASE_URL before logging it (postgres://USER:PASS@HOST...)
masked_db_url="${DATABASE_URL%%@*}@***"

cat <<EOF
Starting Paperclip
  mode:           $PAPERCLIP_DEPLOYMENT_MODE
  instance:       ${PAPERCLIP_INSTANCE_ID:-prod}
  public URL:     $PAPERCLIP_PUBLIC_URL
  database:       $masked_db_url
  S3 endpoint:    $S3_ENDPOINT
  S3 bucket:      $S3_BUCKET
  Vertex region:  $CLOUD_ML_REGION
  Vertex project: $ANTHROPIC_VERTEX_PROJECT_ID
  PORT:           ${PORT:-8080}
EOF

# -----------------------------------------------------------------------------
# Hand off to Paperclip's server
# -----------------------------------------------------------------------------
# `pnpm start` is the canonical entry per Paperclip's package.json. If
# upstream renames it (e.g. to `pnpm run server` or `node dist/server.js`),
# update this line.
exec pnpm start
