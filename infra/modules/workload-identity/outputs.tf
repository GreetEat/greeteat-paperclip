output "pool_name" {
  description = "Full WIF pool resource name (projects/<num>/locations/global/workloadIdentityPools/paperclip-github). Used by GitHub Actions in google-github-actions/auth's workload_identity_provider input."
  value       = google_iam_workload_identity_pool.github.name
}

output "provider_name" {
  description = "Full WIF provider resource name. The GitHub Actions auth step references this exact string."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "Email of the SA that GitHub Actions impersonates via WIF. Passed to the artifact-registry module for the writer grant and to the compute module's serviceAccountUser binding."
  value       = google_service_account.github_actions.email
}
