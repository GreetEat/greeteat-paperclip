output "master_key_secret_id" {
  description = "Secret Manager resource ID of the paperclip-master-key secret. Cloud Run mounts it as PAPERCLIP_SECRETS_MASTER_KEY via env value source."
  value       = data.google_secret_manager_secret.master_key.id
}

output "s3_access_key_id_secret_id" {
  description = "Secret Manager resource ID for the GCS HMAC access ID. Cloud Run mounts as S3_ACCESS_KEY_ID."
  value       = data.google_secret_manager_secret.s3_access_key_id.id
}

output "s3_secret_access_key_secret_id" {
  description = "Secret Manager resource ID for the GCS HMAC secret. Cloud Run mounts as S3_SECRET_ACCESS_KEY."
  value       = data.google_secret_manager_secret.s3_secret_access_key.id
}

output "secret_short_names" {
  description = "Map of canonical short names to bare secret IDs (paperclip-*). Useful for Cloud Run secret mounts that take just the short name + version."
  value = {
    master_key           = data.google_secret_manager_secret.master_key.secret_id
    s3_access_key_id     = data.google_secret_manager_secret.s3_access_key_id.secret_id
    s3_secret_access_key = data.google_secret_manager_secret.s3_secret_access_key.secret_id
  }
}
