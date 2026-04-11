# =============================================================================
# Module: database
# =============================================================================
# Cloud SQL for PostgreSQL 17 with private IP, regional HA, automated
# backups + PITR. Plus the `paperclip` database, the `paperclip` user
# (with a generated password), and the paperclip-database-url Secret
# Manager entry that holds the connection string for Cloud Run to
# mount as DATABASE_URL.
#
# IAM access for the runtime SA to the database-url secret is added by
# the compute module in Phase 3, not here, to avoid the database ↔
# compute circular reference.
# =============================================================================

resource "google_sql_database_instance" "paperclip_pg" {
  name             = "paperclip-pg"
  database_version = "POSTGRES_17"
  region           = var.region
  project          = var.project_id

  deletion_protection = true

  settings {
    tier              = var.cloud_sql_tier
    availability_type = var.cloud_sql_availability_type # REGIONAL = HA
    edition           = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = false            # no public IP
      private_network = var.vpc_id       # peering via PSA
      ssl_mode        = "ENCRYPTED_ONLY" # Cloud SQL enforces SSL on connections
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.cloud_sql_backup_retention_days
      backup_retention_settings {
        retained_backups = var.cloud_sql_backup_retention_days
        retention_unit   = "COUNT"
      }
      start_time = "03:00" # UTC, low-traffic window for us-central1
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    user_labels = {
      service = "paperclip"
    }
  }

  # Private Services Access peering must exist before the instance is created.
  depends_on = [var.private_service_connection_id]
}

resource "google_sql_database" "paperclip" {
  name     = "paperclip"
  instance = google_sql_database_instance.paperclip_pg.name
  project  = var.project_id

  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Generate a strong random password for the paperclip user.
# special = false avoids URL-encoding pain in the connection string.
resource "random_password" "db_password" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "google_sql_user" "paperclip" {
  name     = "paperclip"
  instance = google_sql_database_instance.paperclip_pg.name
  project  = var.project_id
  password = random_password.db_password.result
}

# Connection string for Cloud Run.
#
# `?sslmode=require` is REQUIRED on the URL because Cloud SQL is configured
# with `ssl_mode = ENCRYPTED_ONLY` above, and the postgres.js client (which
# Paperclip uses, see node_modules/.pnpm/postgres@3.4.8) does NOT auto-
# negotiate SSL on a private-IP connection — it connects in cleartext by
# default and Cloud SQL's pg_hba.conf rejects the auth handshake with:
#
#   PostgresError: pg_hba.conf rejects connection for host "10.8.0.x",
#     user "paperclip", database "paperclip", no encryption
#
# Caught the hard way during the first Phase 3 apply. The earlier comment
# claimed pg_client_over_private_ip_negotiates_SSL_automatically — that's
# true for some pg client libraries (e.g. node-postgres / pg) but NOT for
# postgres.js. Since we don't control which client Paperclip uses, the
# only safe thing is to put sslmode in the URL.
#
# `require` (encrypt without verifying the cert chain) is sufficient: the
# connection only ever happens over the VPC private IP, so MITM is not in
# the threat model. `verify-ca` / `verify-full` would require mounting
# Cloud SQL's server CA cert into the container, which adds complexity
# without security benefit on a private network.
locals {
  database_url = "postgres://paperclip:${random_password.db_password.result}@${google_sql_database_instance.paperclip_pg.private_ip_address}:5432/paperclip?sslmode=require"
}

resource "google_secret_manager_secret" "database_url" {
  secret_id = "paperclip-database-url"
  project   = var.project_id

  labels = {
    service = "paperclip"
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = local.database_url
}
