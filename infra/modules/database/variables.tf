variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region for the Cloud SQL instance."
}

variable "vpc_id" {
  type        = string
  description = "VPC self-link from the network module. Cloud SQL attaches its private IP to this VPC via Private Services Access peering."
}

variable "private_service_connection_id" {
  type        = string
  description = "google_service_networking_connection ID from the network module. Used as a depends_on anchor so Cloud SQL is not created until the PSA peering is established."
}

variable "cloud_sql_tier" {
  type        = string
  description = "Cloud SQL machine tier (e.g. db-custom-2-7680)."
}

variable "cloud_sql_availability_type" {
  type        = string
  description = "Cloud SQL availability type — must be REGIONAL for the single-env production deployment."

  validation {
    condition     = var.cloud_sql_availability_type == "REGIONAL"
    error_message = "Single-env deployment requires REGIONAL HA."
  }
}

variable "cloud_sql_backup_retention_days" {
  type        = number
  description = "Number of days of backups + transaction log to retain for point-in-time recovery."

  validation {
    condition     = var.cloud_sql_backup_retention_days >= 1
    error_message = "Backup retention must be at least 1 day."
  }
}
