# =============================================================================
# Module: storage
# =============================================================================
# Creates the paperclip-492823-uploads GCS bucket for Paperclip user
# uploads, and grants storage.objectUser to the paperclip-storage-sa
# service account that owns the HMAC key Paperclip uses via the S3
# interop API.
#
# The runtime SA (paperclip-runtime-sa) does NOT need direct bucket
# access — Paperclip's S3 storage backend authenticates via HMAC keys
# in AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, which are tied to
# paperclip-storage-sa's IAM grant on the bucket. See contracts/
# container-image.md for the env var mapping.
# =============================================================================

resource "google_storage_bucket" "uploads" {
  name                        = "paperclip-492823-uploads"
  location                    = var.region
  project                     = var.project_id
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 7
    }
  }

  labels = {
    service = "paperclip"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Look up paperclip-storage-sa, which was created by bootstrap-gcs-hmac.sh
# (T013 / T023). If this data lookup fails, the operator hasn't run the
# bootstrap script — that's the safety check we want.
data "google_service_account" "storage_sa" {
  account_id = "paperclip-storage-sa"
  project    = var.project_id
}

# Grant paperclip-storage-sa storage.objectUser on its own bucket.
# This is what the HMAC key carries — the SA's permissions on the bucket
# determine what the S3 interop API allows Paperclip to do.
resource "google_storage_bucket_iam_member" "storage_sa_object_user" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${data.google_service_account.storage_sa.email}"
}
