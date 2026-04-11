# =============================================================================
# Module: edge
# =============================================================================
# Cloud DNS managed zone for the deployment domain + Cloud Run domain
# mapping that binds the custom hostname to the paperclip Cloud Run
# service. Google manages the TLS certificate automatically via the
# domain mapping.
#
# Operator action required after the first apply: delegate the
# var.domain DNS zone to Google Cloud DNS by updating NS records at
# the domain registrar. The terraform output `name_servers` lists the
# NS values to use.
# =============================================================================

resource "google_dns_managed_zone" "paperclip_zone" {
  name        = "paperclip-greeteat-zone"
  dns_name    = "${var.domain}."
  description = "Cloud DNS zone for the Paperclip deployment domain. Operator delegates this zone to Google Cloud DNS by updating NS records at the registrar."
  project     = var.project_id

  visibility = "public"

  dnssec_config {
    state = "on"
  }

  labels = {
    service = "paperclip"
  }
}

# CNAME record pointing the deployment hostname at Cloud Run's hosted
# Google service endpoint. This is what the Cloud Run domain mapping
# expects for subdomain hostnames.
resource "google_dns_record_set" "paperclip_cname" {
  name         = "${var.domain}."
  managed_zone = google_dns_managed_zone.paperclip_zone.name
  type         = "CNAME"
  ttl          = 300
  project      = var.project_id

  rrdatas = ["ghs.googlehosted.com."]
}

# Cloud Run domain mapping — binds the custom hostname to the Cloud Run
# v2 service. This is the v1 google_cloud_run_domain_mapping resource;
# per the Google provider docs it works against v2 services as well as
# v1. Google manages the TLS cert automatically.
resource "google_cloud_run_domain_mapping" "paperclip" {
  name     = var.domain
  location = var.region
  project  = var.project_id

  metadata {
    namespace = var.project_id
    labels = {
      service = "paperclip"
    }
  }

  spec {
    route_name = var.cloud_run_service_name
  }
}
