output "service_account_email" {
  description = "Email of paperclip-runtime-sa. Available for any future module that needs to grant the runtime SA additional access."
  value       = google_service_account.runtime_sa.email
}

output "service_name" {
  description = "Cloud Run service name (paperclip). Used by the edge module's domain mapping."
  value       = google_cloud_run_v2_service.paperclip.name
}

output "service_uri" {
  description = "Cloud Run-assigned *.run.app URL (the default URL before the custom domain mapping is applied). Useful as a fallback during bring-up."
  value       = google_cloud_run_v2_service.paperclip.uri
}

output "service_id" {
  description = "Cloud Run service full resource ID."
  value       = google_cloud_run_v2_service.paperclip.id
}

output "latest_revision" {
  description = "Name of the latest created revision. Used by deploy.sh / rollback.sh as the rollback target after each apply."
  value       = google_cloud_run_v2_service.paperclip.latest_created_revision
}
