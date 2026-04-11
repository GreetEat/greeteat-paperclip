variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region."
}

variable "public_url" {
  type        = string
  description = "Full public URL Paperclip is reachable at, including https:// scheme. Used as PAPERCLIP_PUBLIC_URL. The prod env composer derives this from var.domain (if a custom domain is set) or var.public_url_override (after the first apply, when the *.run.app URL is known) or a placeholder (during the first apply of a no-domain deployment)."

  validation {
    condition     = can(regex("^https://", var.public_url))
    error_message = "public_url must start with https://."
  }
}

# -----------------------------------------------------------------------------
# Cloud Run service shape
# -----------------------------------------------------------------------------

variable "paperclip_image_url" {
  type        = string
  description = "Artifact Registry image URL prefix WITHOUT tag/digest, e.g. us-central1-docker.pkg.dev/paperclip-492823/paperclip/paperclip. The compute module appends @<digest>."
}

variable "paperclip_image_digest" {
  type        = string
  description = "Immutable Artifact Registry image digest (sha256:...). Pinned in versions.tfvars; updated after each CI build."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.paperclip_image_digest))
    error_message = "paperclip_image_digest must match sha256:<64 hex chars>. Run the build-image.yml workflow first to produce a digest."
  }
}

variable "cloud_run_min_instances" {
  type        = number
  description = "Cloud Run min-instances. Must be >= 2 for the single-env deployment."
}

variable "cloud_run_max_instances" {
  type        = number
  description = "Cloud Run max-instances ceiling."
}

variable "cloud_run_cpu" {
  type        = string
  description = "Cloud Run CPU allocation per instance."
}

variable "cloud_run_memory" {
  type        = string
  description = "Cloud Run memory allocation per instance."
}

variable "vpc_connector_id" {
  type        = string
  description = "Serverless VPC Connector ID from the network module. Cloud Run egress to private RFC1918 ranges (Cloud SQL) routes through this."
}

# -----------------------------------------------------------------------------
# Inputs from sibling modules — IDs of resources the runtime SA needs to access
# -----------------------------------------------------------------------------

variable "artifact_registry_repository_id" {
  type        = string
  description = "Repository ID (short name) of the paperclip Artifact Registry repo. The runtime SA gets roles/artifactregistry.reader on this for image pulls."
}

variable "storage_bucket_name" {
  type        = string
  description = "Name of the uploads bucket. Used as the value of PAPERCLIP_STORAGE_S3_BUCKET. The runtime SA does NOT need direct bucket IAM — Paperclip uses HMAC creds for the storage backend."
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

variable "s3_access_key_id_secret_id" {
  type        = string
  description = "Full Secret Manager resource ID of paperclip-s3-access-key-id (from secrets module). Mounted as AWS_ACCESS_KEY_ID."
}

variable "s3_secret_access_key_secret_id" {
  type        = string
  description = "Full Secret Manager resource ID of paperclip-s3-secret-access-key (from secrets module). Mounted as AWS_SECRET_ACCESS_KEY."
}
