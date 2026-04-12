output "bucket_name" {
  description = "Name of the uploads bucket. Used by the compute module as the value of PAPERCLIP_STORAGE_S3_BUCKET."
  value       = google_storage_bucket.uploads.name
}

output "bucket_url" {
  description = "Full gs:// URL of the uploads bucket."
  value       = google_storage_bucket.uploads.url
}

output "state_bucket_name" {
  description = "Name of the state bucket. Mounted via GCS FUSE at /paperclip on Cloud Run service and jobs to persist agent instructions, memory, workspaces, and config across instance recycles."
  value       = google_storage_bucket.state.name
}
