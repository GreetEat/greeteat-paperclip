output "name_servers" {
  description = "Cloud DNS name servers for the deployment domain. **Operator action required**: update NS records for var.domain at the domain registrar to delegate this zone to Google Cloud DNS."
  value       = google_dns_managed_zone.paperclip_zone.name_servers
}

output "dns_name" {
  description = "Fully-qualified DNS name (with trailing dot) of the managed zone."
  value       = google_dns_managed_zone.paperclip_zone.dns_name
}

output "domain_mapping_status" {
  description = "Status conditions of the Cloud Run domain mapping. Watch for status to become READY (Google-managed cert provisioning takes 5-15 minutes on first apply)."
  value       = google_cloud_run_domain_mapping.paperclip.status
}
