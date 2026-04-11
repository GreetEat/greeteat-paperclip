# =============================================================================
# Outputs for the Paperclip GreetEat prod environment.
# =============================================================================
# Operators read these via `terraform output <name>` after each apply.
# The most important one for first-time bring-up is service_uri (used to
# fill `public_url_override` for the second pass of the no-domain bootstrap).

output "service_uri" {
  description = "Cloud Run-assigned *.run.app URL of the paperclip service. After the first apply of a no-domain deployment, copy this exact value into `public_url_override` in terraform.tfvars and re-apply so PAPERCLIP_PUBLIC_URL matches the request origin (Better Auth's trustedOrigins requirement)."
  value       = module.compute.service_uri
}

output "service_name" {
  description = "Cloud Run service name (paperclip). Used by `gcloud run services` commands when manually inspecting or rolling traffic."
  value       = module.compute.service_name
}

output "runtime_service_account_email" {
  description = "Email of the paperclip-runtime-sa service account. Useful for granting additional IAM out-of-band when developing new features."
  value       = module.compute.service_account_email
}

output "bootstrap_ceo_job_name" {
  description = "Name of the bootstrap-ceo Cloud Run Job. After Phase 3 apply, run: gcloud run jobs execute <name> --region=us-central1 --project=paperclip-492823 --wait — then read the execution log for the one-time invite URL (T034)."
  value       = module.jobs.bootstrap_ceo_job_name
}

output "edge_name_servers" {
  description = "Cloud DNS name servers for the deployment domain (only populated when var.domain is set and the edge module is active). Operator delegates the zone by updating NS records at the registrar."
  value       = var.domain != "" ? module.edge[0].name_servers : null
}
