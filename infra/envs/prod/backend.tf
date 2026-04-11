# Terraform state backend for the prod (single) environment.
#
# Bucket is created manually as a one-time operator prerequisite (T011 in
# tasks.md, also covered in quickstart.md Section 1c). Object versioning
# is enabled on the bucket so prior plan/apply states are recoverable.

terraform {
  backend "gcs" {
    # Project-prefixed because GCS bucket names are globally unique across
    # all GCP customers — `paperclip-tf-state` was already taken when we
    # tried T011. Project IDs are unique by definition, so prefixing with
    # the project ID guarantees this name is available to us forever.
    bucket = "paperclip-492823-tf-state"
    prefix = "envs/prod"
  }
}
