# =============================================================================
# Module: artifact-registry
# =============================================================================
# Creates the `paperclip` Docker repository in Artifact Registry where
# build-image.yml pushes Paperclip container images. Conditionally grants
# writer access to the GitHub Actions service account (created by the
# workload-identity module) and reader access to the Cloud Run runtime
# service account (created by the compute module in Phase 3).
# =============================================================================

resource "google_artifact_registry_repository" "paperclip" {
  repository_id = "paperclip"
  location      = var.region
  format        = "DOCKER"
  project       = var.project_id

  description = "Paperclip container images. Built from pinned upstream Paperclip release tags by .github/workflows/build-image.yml. Consumed by Cloud Run via immutable digest references in versions.tfvars."

  labels = {
    service = "paperclip"
  }

  docker_config {
    # We tag images with both <paperclip-version> and <git-sha>, so immutable
    # tags would prevent re-tagging on rebuild of the same Paperclip version.
    # Image identity is enforced via digest pinning in versions.tfvars instead.
    immutable_tags = false
  }
}

# Writer access for GitHub Actions (image push). Conditional because the
# workload-identity module is instantiated in the same Phase 2 batch and
# we want graceful behavior if WIF lands first / second.
resource "google_artifact_registry_repository_iam_member" "github_actions_writer" {
  count = var.github_actions_service_account_email == null ? 0 : 1

  project    = google_artifact_registry_repository.paperclip.project
  location   = google_artifact_registry_repository.paperclip.location
  repository = google_artifact_registry_repository.paperclip.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.github_actions_service_account_email}"
}

# Reader access for the Cloud Run runtime SA (image pull). Conditional
# because the compute module creates this SA in Phase 3.
resource "google_artifact_registry_repository_iam_member" "runtime_reader" {
  count = var.runtime_service_account_email == null ? 0 : 1

  project    = google_artifact_registry_repository.paperclip.project
  location   = google_artifact_registry_repository.paperclip.location
  repository = google_artifact_registry_repository.paperclip.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.runtime_service_account_email}"
}
