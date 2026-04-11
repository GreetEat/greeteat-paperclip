#!/usr/bin/env bash
# =============================================================================
# bootstrap-master-key.sh
# =============================================================================
# One-time prerequisite: generate the Paperclip secrets master encryption key
# and store it in GCP Secret Manager as `paperclip-master-key`.
#
# This script is IDEMPOTENT in the safe direction: it refuses to overwrite an
# existing secret. Re-running it on a project that already has the master key
# is a no-op with a warning. To rotate, use a separate (future) rotation
# procedure that creates a new version on the existing secret — DO NOT delete
# and recreate the secret because Paperclip's encrypted secret store will
# become unrecoverable.
#
# The generated key is NEVER written to disk. It's piped from `openssl rand`
# directly into `gcloud secrets versions add --data-file=-` so the value only
# exists in memory and inside Secret Manager.
#
# Usage:
#   ./infra/scripts/bootstrap-master-key.sh
#
# Prerequisites:
#   - gcloud authenticated as an account with secretmanager.admin on
#     paperclip-492823
#   - Secret Manager API enabled (terraform apply against the apis module
#     handles this; or `gcloud services enable secretmanager.googleapis.com`)
# =============================================================================

set -euo pipefail

PROJECT_ID="${PROJECT_ID:-paperclip-492823}"
SECRET_NAME="paperclip-master-key"
LABEL="service=paperclip"

# Sanity-check we're authenticated to the right project
active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")
if [ -z "$active_account" ]; then
  echo "ERROR: no active gcloud account. Run: gcloud auth login" >&2
  exit 1
fi

current_project=$(gcloud config get-value project 2>/dev/null || echo "")
if [ "$current_project" != "$PROJECT_ID" ]; then
  echo "WARNING: gcloud current project is '$current_project', not '$PROJECT_ID'." >&2
  echo "         This script will operate on '$PROJECT_ID' regardless." >&2
fi

# Refuse to overwrite an existing secret
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "ERROR: secret '$SECRET_NAME' already exists in $PROJECT_ID." >&2
  echo "       This script refuses to overwrite to avoid destroying the existing key." >&2
  echo "       To rotate, follow the documented rotation procedure (research.md Decision 5 followup)." >&2
  exit 2
fi

echo "Generating 32-byte master key and creating Secret Manager secret '$SECRET_NAME' in $PROJECT_ID ..."

# Create the secret entry first (no value yet)
gcloud secrets create "$SECRET_NAME" \
  --project="$PROJECT_ID" \
  --replication-policy="automatic" \
  --labels="$LABEL"

# Then add the first version, piping the random bytes directly from openssl.
# The key is base64-encoded for safe transit through env vars at runtime.
openssl rand -base64 32 | gcloud secrets versions add "$SECRET_NAME" \
  --project="$PROJECT_ID" \
  --data-file=-

echo "✓ Secret '$SECRET_NAME' created in $PROJECT_ID"
echo ""
echo "The master key value is in Secret Manager only. It was never written to disk."
echo "Verify with:"
echo "  gcloud secrets versions list $SECRET_NAME --project=$PROJECT_ID"
