output "master_key_secret_id" {
  description = "Secret Manager resource ID of the paperclip-master-key secret. Cloud Run mounts it as PAPERCLIP_SECRETS_MASTER_KEY via env value source — Paperclip's local-encrypted secret provider reads it directly from the env var (server/src/secrets/local-encrypted-provider.ts)."
  value       = data.google_secret_manager_secret.master_key.id
}

output "better_auth_secret_secret_id" {
  description = "Secret Manager resource ID of the paperclip-better-auth-secret. Cloud Run mounts it as BETTER_AUTH_SECRET via env value source. Paperclip's Better Auth integration uses it to sign cookies/JWTs (server/src/auth/better-auth.ts), and PAPERCLIP_AGENT_JWT_SECRET falls back to the same value, so one secret covers both auth paths."
  value       = data.google_secret_manager_secret.better_auth_secret.id
}

output "s3_access_key_id_secret_id" {
  description = "Secret Manager resource ID for the GCS HMAC access ID. Cloud Run mounts as AWS_ACCESS_KEY_ID — Paperclip's S3 storage provider creates an S3Client without explicit credentials and the AWS SDK falls back to the standard AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars (server/src/storage/s3-provider.ts)."
  value       = data.google_secret_manager_secret.s3_access_key_id.id
}

output "s3_secret_access_key_secret_id" {
  description = "Secret Manager resource ID for the GCS HMAC secret. Cloud Run mounts as AWS_SECRET_ACCESS_KEY (see master_key_secret_id output for the rationale)."
  value       = data.google_secret_manager_secret.s3_secret_access_key.id
}

output "secret_short_names" {
  description = "Map of canonical short names to bare secret IDs (paperclip-*). Useful for Cloud Run secret mounts that take just the short name + version."
  value = {
    master_key            = data.google_secret_manager_secret.master_key.secret_id
    better_auth_secret    = data.google_secret_manager_secret.better_auth_secret.secret_id
    s3_access_key_id      = data.google_secret_manager_secret.s3_access_key_id.secret_id
    s3_secret_access_key  = data.google_secret_manager_secret.s3_secret_access_key.secret_id
  }
}
