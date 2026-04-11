# =============================================================================
# Module: secrets
# =============================================================================
# Looks up the four bootstrap-created Secret Manager secrets and exposes
# their resource IDs to other modules. Pure data-lookup module — does NOT
# create IAM bindings.
#
# IAM bindings on the Cloud Run runtime service account are created by
# the compute module (in Phase 3), not here. This avoids a circular
# module reference between secrets ↔ compute (compute reads secret IDs
# from this module while also creating the SA that needs IAM access).
#
# The fifth secret — paperclip-database-url — is created by the database
# module in Phase 3 (the password is generated as part of Cloud SQL user
# creation), and its IAM binding is also added by the compute module
# alongside the bindings on these four secrets.
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
