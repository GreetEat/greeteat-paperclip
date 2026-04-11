#!/usr/bin/env bash
# =============================================================================
# bootstrap-better-auth-secret.sh
# =============================================================================
# One-time prerequisite: generate the BETTER_AUTH_SECRET that Paperclip's
# Better Auth integration uses to sign session cookies and JWTs, and store
# it in GCP Secret Manager as `paperclip-better-auth-secret`.
#
# Sibling of bootstrap-master-key.sh — same idempotent pattern, same
# 32-byte random secret shape, just a different secret name. Both are
# Paperclip-required for any authenticated deployment.
#
# Per Paperclip's source (server/src/auth/better-auth.ts), BETTER_AUTH_SECRET
# is consulted first; if missing, PAPERCLIP_AGENT_JWT_SECRET is used as a
# fallback. We set BETTER_AUTH_SECRET (the canonical name) and let agent JWT
# auth fall back to it — one secret, both purposes.
#
# This script is IDEMPOTENT in the safe direction: it refuses to overwrite
# an existing secret. Re-running it on a project that already has the
# better-auth secret is a no-op with a warning. Rotating it WILL invalidate
# all existing board operator sessions (operators will be forced to sign
# in again) — only do that intentionally.
#
# The generated value is NEVER written to disk. It's piped from
# `openssl rand` directly into `gcloud secrets versions add --data-file=-`
# so the value only exists in memory and inside Secret Manager.
#
# Usage:
#   ./infra/scripts/bootstrap-better-auth-secret.sh
#
# Prerequisites:
#   - gcloud authenticated as an account with secretmanager.admin on
#     paperclip-492823
#   - Secret Manager API enabled
# =============================================================================

set -euo pipefail

PROJECT_ID="${PROJECT_ID:-paperclip-492823}"
SECRET_NAME="paperclip-better-auth-secret"
LABEL="service=paperclip"

# Sanity-check authentication
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
  echo "       This script refuses to overwrite. Rotating BETTER_AUTH_SECRET" >&2
  echo "       invalidates all existing board operator sessions; only do that" >&2
  echo "       intentionally via a separate rotation procedure." >&2
  exit 2
fi

echo "Generating 32-byte random secret and creating Secret Manager secret '$SECRET_NAME' in $PROJECT_ID ..."

gcloud secrets create "$SECRET_NAME" \
  --project="$PROJECT_ID" \
  --replication-policy="automatic" \
  --labels="$LABEL"

openssl rand -base64 32 | gcloud secrets versions add "$SECRET_NAME" \
  --project="$PROJECT_ID" \
  --data-file=-

echo "✓ Secret '$SECRET_NAME' created in $PROJECT_ID"
echo ""
echo "The secret value is in Secret Manager only. It was never written to disk."
echo "Cloud Run will mount it as the BETTER_AUTH_SECRET env var via the"
echo "task spec's secrets field. PAPERCLIP_AGENT_JWT_SECRET also falls back"
echo "to this same value, so agent JWT auth and Better Auth share one secret."
echo ""
echo "Verify with:"
echo "  gcloud secrets versions list $SECRET_NAME --project=$PROJECT_ID"
