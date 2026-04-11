variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "runtime_service_account_email" {
  type        = string
  description = "Email of the Cloud Run runtime service account that should receive `roles/secretmanager.secretAccessor` on each Paperclip secret. Pass null in Phase 2 (no SA exists yet — just validates secrets exist via the data lookups). Pass the actual email in Phase 3 once compute module creates paperclip-runtime-sa."
  default     = null
}
