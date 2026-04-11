# =============================================================================
# Module: secrets
# =============================================================================
# Looks up the Secret Manager secrets created by the bootstrap scripts
# (bootstrap-master-key.sh, bootstrap-gcs-hmac.sh) and conditionally grants
# `roles/secretmanager.secretAccessor` to the Cloud Run runtime service
# account on each.
#
# Phase 2 (T022) instantiates this module WITHOUT runtime_service_account_email
# — at that point, the data lookups validate that the bootstrap scripts have
# run, but no IAM bindings are created.
#
# Phase 3 (T032) updates the instantiation to pass the actual SA email from
# the compute module, which activates the IAM bindings.
#
# The fourth secret — paperclip-database-url — is created by the database
# module in Phase 3 (the password is generated as part of Cloud SQL user
# creation). Its IAM binding lives in the database module, not here.
# =============================================================================

data "google_secret_manager_secret" "master_key" {
  secret_id = "paperclip-master-key"
  project   = var.project_id
}

data "google_secret_manager_secret" "better_auth_secret" {
  secret_id = "paperclip-better-auth-secret"
  project   = var.project_id
}

data "google_secret_manager_secret" "s3_access_key_id" {
  secret_id = "paperclip-s3-access-key-id"
  project   = var.project_id
}

data "google_secret_manager_secret" "s3_secret_access_key" {
  secret_id = "paperclip-s3-secret-access-key"
  project   = var.project_id
}

# IAM bindings: only created when the runtime SA email is provided.
locals {
  secret_ids_for_iam = var.runtime_service_account_email == null ? [] : [
    data.google_secret_manager_secret.master_key.id,
    data.google_secret_manager_secret.better_auth_secret.id,
    data.google_secret_manager_secret.s3_access_key_id.id,
    data.google_secret_manager_secret.s3_secret_access_key.id,
  ]
}

resource "google_secret_manager_secret_iam_member" "runtime_access" {
  for_each = toset(local.secret_ids_for_iam)

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.runtime_service_account_email}"
}
