# Terraform state backend for the prod (single) environment.
#
# Bucket is created manually as a one-time operator prerequisite (T011 in
# tasks.md, also covered in quickstart.md Section 1c). Object versioning
# is enabled on the bucket so prior plan/apply states are recoverable.

terraform {
  backend "gcs" {
    bucket = "paperclip-tf-state"
    prefix = "envs/prod"
  }
}
