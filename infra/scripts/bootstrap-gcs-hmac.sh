#!/usr/bin/env bash
# =============================================================================
# bootstrap-gcs-hmac.sh
# =============================================================================
# One-time prerequisite: create the dedicated GCS storage service account,
# generate an HMAC key against it, and store the access ID + secret in
# Secret Manager as `paperclip-s3-access-key-id` and
# `paperclip-s3-secret-access-key`.
#
# Paperclip uses GCS via the S3-compatible interop API at
# storage.googleapis.com. The interop API authenticates with HMAC keys, not
# IAM tokens — that's why we need this bootstrap step rather than just
# attaching the Cloud Run service account.
#
# This script is IDEMPOTENT in the safe direction: it refuses to overwrite
# existing secrets. The bucket-level IAM grant (storage.objectUser on the
# uploads bucket) is added by the storage Terraform module in Phase 3.
#
# Usage:
#   ./infra/scripts/bootstrap-gcs-hmac.sh
#
# Prerequisites:
#   - gcloud authenticated as an account with iam.serviceAccountAdmin
#     and secretmanager.admin on paperclip-492823
#   - Secret Manager API + IAM API enabled
# =============================================================================

set -euo pipefail

PROJECT_ID="${PROJECT_ID:-paperclip-492823}"
SA_ID="paperclip-storage-sa"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
ACCESS_KEY_SECRET="paperclip-s3-access-key-id"
SECRET_KEY_SECRET="paperclip-s3-secret-access-key"
LABEL="service=paperclip"

# Sanity-check authentication
active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")
if [ -z "$active_account" ]; then
  echo "ERROR: no active gcloud account. Run: gcloud auth login" >&2
  exit 1
fi

# Refuse to overwrite existing secrets
for s in "$ACCESS_KEY_SECRET" "$SECRET_KEY_SECRET"; do
  if gcloud secrets describe "$s" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "ERROR: secret '$s' already exists in $PROJECT_ID." >&2
    echo "       This script refuses to overwrite to avoid breaking the live HMAC key." >&2
    echo "       To rotate, generate a new HMAC key against $SA_EMAIL and add a new" >&2
    echo "       version to the existing secrets, then re-deploy Cloud Run." >&2
    exit 2
  fi
done

# Create the storage service account if missing
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Creating service account $SA_EMAIL ..."
  gcloud iam service-accounts create "$SA_ID" \
    --project="$PROJECT_ID" \
    --display-name="Paperclip storage (GCS interop)" \
    --description="Owns the HMAC key Paperclip uses to access greeteat-paperclip-uploads via the S3 interop API. The bucket-level storage.objectUser grant is in the Terraform storage module."
else
  echo "Service account $SA_EMAIL already exists, reusing."
fi

# Generate the HMAC key
echo "Generating HMAC key for $SA_EMAIL ..."
hmac_json=$(gcloud storage hmac create "$SA_EMAIL" --project="$PROJECT_ID" --format=json)

access_id=$(echo "$hmac_json" | jq -r '.accessId')
secret=$(echo "$hmac_json" | jq -r '.secret')

if [ -z "$access_id" ] || [ -z "$secret" ]; then
  echo "ERROR: failed to parse HMAC key from gcloud output" >&2
  exit 3
fi

# Store the access ID
gcloud secrets create "$ACCESS_KEY_SECRET" \
  --project="$PROJECT_ID" \
  --replication-policy="automatic" \
  --labels="$LABEL"
printf '%s' "$access_id" | gcloud secrets versions add "$ACCESS_KEY_SECRET" \
  --project="$PROJECT_ID" \
  --data-file=-

# Store the secret
gcloud secrets create "$SECRET_KEY_SECRET" \
  --project="$PROJECT_ID" \
  --replication-policy="automatic" \
  --labels="$LABEL"
printf '%s' "$secret" | gcloud secrets versions add "$SECRET_KEY_SECRET" \
  --project="$PROJECT_ID" \
  --data-file=-

# Clear the local variables holding the secret material
unset secret
unset hmac_json

echo ""
echo "✓ HMAC key created against $SA_EMAIL"
echo "✓ Secret '$ACCESS_KEY_SECRET' stored in $PROJECT_ID"
echo "✓ Secret '$SECRET_KEY_SECRET' stored in $PROJECT_ID"
echo ""
echo "Verify with:"
echo "  gcloud secrets versions list $ACCESS_KEY_SECRET --project=$PROJECT_ID"
echo "  gcloud secrets versions list $SECRET_KEY_SECRET --project=$PROJECT_ID"
echo "  gcloud storage hmac list --project=$PROJECT_ID"
