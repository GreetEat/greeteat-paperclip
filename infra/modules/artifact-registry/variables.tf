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

variable "runtime_service_account_email" {
  type        = string
  description = "Email of the Cloud Run runtime service account that pulls images. Pass null in Phase 2; pass the actual email in Phase 3 once compute module creates paperclip-runtime-sa."
  default     = null
}
