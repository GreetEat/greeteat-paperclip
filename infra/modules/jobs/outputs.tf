output "bootstrap_ceo_job_name" {
  description = "Name of the bootstrap-ceo Cloud Run Job. Operator runs `gcloud run jobs execute <name> --region=us-central1 --project=paperclip-492823 --wait` to seed the first board operator (T034)."
  value       = google_cloud_run_v2_job.bootstrap_ceo.name
}

output "bootstrap_ceo_job_id" {
  description = "Full resource ID of the bootstrap-ceo Cloud Run Job."
  value       = google_cloud_run_v2_job.bootstrap_ceo.id
}
