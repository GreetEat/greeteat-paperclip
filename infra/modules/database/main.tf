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

# Connection string for Cloud Run. Postgres SSL is enforced via Cloud SQL's
# ssl_mode, but the URL itself doesn't need explicit sslmode= because the
# pg client over private IP negotiates SSL automatically.
locals {
  database_url = "postgres://paperclip:${random_password.db_password.result}@${google_sql_database_instance.paperclip_pg.private_ip_address}:5432/paperclip"
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
