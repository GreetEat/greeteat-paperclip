variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region for the Artifact Registry repository."
}

variable "github_actions_service_account_email" {
  type        = string
  description = "Email of the GitHub Actions WIF service account that pushes images. Pass null if the workload-identity module hasn't been instantiated yet."
  default     = null
}
