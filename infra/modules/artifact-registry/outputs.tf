output "repository_id" {
  value = google_artifact_registry_repository.paperclip.repository_id
}

output "repository_url" {
  description = "Fully-qualified Artifact Registry image URL prefix (without tag/digest). Used by build-image.yml as the docker push target and by Cloud Run service spec as the image base."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.paperclip.repository_id}"
}
