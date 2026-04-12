variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region. Must match the Cloud Run service region so the job can use the same VPC connector and reach the same Cloud SQL private IP."
}

variable "public_url" {
  type        = string
  description = "Full public URL Paperclip is reachable at, including https:// scheme. Used as PAPERCLIP_PUBLIC_URL inside the job and as the bootstrap-ceo --base-url argument so the printed invite link points at the live deployment. Composed by the prod env (see compute module's public_url for the same composition)."

  validation {
    condition     = can(regex("^https://", var.public_url))
    error_message = "public_url must start with https://."
  }
}

variable "paperclip_image_url" {
  type        = string
  description = "Artifact Registry image URL prefix WITHOUT tag/digest. Same value passed to the compute module so the job runs the byte-identical image as the live service."
}

variable "paperclip_image_digest" {
  type        = string
  description = "Immutable Artifact Registry image digest (sha256:...). Pinned in versions.tfvars; updated after each CI build."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.paperclip_image_digest))
    error_message = "paperclip_image_digest must match sha256:<64 hex chars>."
  }
}

variable "vpc_connector_id" {
  type        = string
  description = "Serverless VPC Connector ID from the network module. Required so the job can reach Cloud SQL via private IP."
}

variable "state_bucket_name" {
  type        = string
  description = "Name of the state bucket. Mounted via GCS FUSE at /paperclip on the Cloud Run Job so the bootstrap-ceo wrapper's config.json write persists and is visible to the live service."
}

variable "runtime_service_account_email" {
  type        = string
  description = "Email of paperclip-runtime-sa from the compute module. The job runs as the same SA the live service runs as so secret IAM and Vertex IAM are already in place."
}

variable "master_key_secret_id" {
  type        = string
  description = "Full Secret Manager resource ID of paperclip-master-key (from secrets module)."
}

variable "better_auth_secret_secret_id" {
  type        = string
  description = "Full Secret Manager resource ID of paperclip-better-auth-secret (from secrets module)."
}

variable "database_url_secret_id" {
  type        = string
  description = "Full Secret Manager resource ID of paperclip-database-url (from database module)."
}
