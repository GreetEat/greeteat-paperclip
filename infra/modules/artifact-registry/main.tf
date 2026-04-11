# =============================================================================
# Module: artifact-registry
# =============================================================================
# Creates the `paperclip` Docker repository in Artifact Registry where
# build-image.yml pushes Paperclip container images. Grants writer access
# to the GitHub Actions service account (created by the workload-identity
# module).
#
# The Cloud Run runtime SA's reader binding is added by the compute module
# in Phase 3, NOT here, to avoid a circular module reference between
# artifact-registry ↔ compute (compute reads the repository ID from this
# module while also creating the SA that needs image-pull access).
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

