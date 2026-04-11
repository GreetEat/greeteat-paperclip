output "instance_name" {
  description = "Cloud SQL instance name (paperclip-pg)."
  value       = google_sql_database_instance.paperclip_pg.name
}

output "instance_connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance). Used by the Cloud SQL Auth Proxy if ever needed; not required for our private-IP path."
  value       = google_sql_database_instance.paperclip_pg.connection_name
}

output "private_ip_address" {
  description = "Cloud SQL instance's private IP address. Used in the DATABASE_URL connection string (already embedded in the database-url secret value)."
  value       = google_sql_database_instance.paperclip_pg.private_ip_address
  sensitive   = true
}

output "database_url_secret_id" {
  description = "Full Secret Manager resource ID of the paperclip-database-url secret. The compute module mounts this as DATABASE_URL via the Cloud Run service spec's env value source."
  value       = google_secret_manager_secret.database_url.id
}
