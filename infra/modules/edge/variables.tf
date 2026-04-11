variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region (matches the Cloud Run service region for the domain mapping)."
}

variable "domain" {
  type        = string
  description = "Public hostname for the Paperclip deployment. The Cloud DNS zone is created for this exact name; the operator must delegate it via NS records at the registrar."
}

variable "cloud_run_service_name" {
  type        = string
  description = "Cloud Run service name from the compute module. The domain mapping binds the custom hostname to this service."
}
