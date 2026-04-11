# =============================================================================
# Module: network
# =============================================================================
# VPC + subnet + Serverless VPC Connector + Private Services Access peering.
# Together these give Cloud Run a private path to Cloud SQL's private IP.
#
# Resources:
#   - paperclip-vpc                  : custom VPC, no auto-created subnets
#   - paperclip-subnet               : private subnet in the configured region
#   - paperclip-connector            : Serverless VPC Connector for Cloud Run
#   - paperclip-private-service-range: address range for Private Services Access
#   - servicenetworking peering      : peering with servicenetworking.googleapis.com
#                                       (allows Cloud SQL to use private IP)
# =============================================================================

resource "google_compute_network" "paperclip_vpc" {
  name                    = "paperclip-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = var.project_id

  description = "Paperclip-managed VPC. Cloud Run reaches Cloud SQL via the Serverless VPC Connector + Private Services Access peering attached to this VPC."
}

resource "google_compute_subnetwork" "paperclip_subnet" {
  name                     = "paperclip-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.paperclip_vpc.id
  project                  = var.project_id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_vpc_access_connector" "paperclip_connector" {
  name    = "paperclip-connector"
  region  = var.region
  project = var.project_id

  subnet {
    name = google_compute_subnetwork.paperclip_subnet.name
  }

  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

# Reserved address range for Private Services Access (Cloud SQL private IP)
resource "google_compute_global_address" "private_service_range" {
  name          = "paperclip-private-service-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.paperclip_vpc.id
  project       = var.project_id

  description = "Reserved range for Private Services Access (Cloud SQL private IP peering)"
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.paperclip_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]

  # ABANDON instead of DELETE on destroy because deleting the peering can
  # leave Cloud SQL in a broken state. The peering is harmless to leave
  # behind if Paperclip is decommissioned.
  deletion_policy = "ABANDON"
}
