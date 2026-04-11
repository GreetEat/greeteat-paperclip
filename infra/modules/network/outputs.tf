output "vpc_id" {
  value       = google_compute_network.paperclip_vpc.id
  description = "Self-link of the Paperclip VPC. Referenced by the database module for Cloud SQL private-IP attachment."
}

output "vpc_self_link" {
  value = google_compute_network.paperclip_vpc.self_link
}

output "subnet_id" {
  value = google_compute_subnetwork.paperclip_subnet.id
}

output "connector_id" {
  description = "Serverless VPC Connector ID. Referenced by the Cloud Run service in the compute module via `vpc_access.connector`."
  value       = google_vpc_access_connector.paperclip_connector.id
}

output "private_service_connection_id" {
  description = "Anchor for the database module to depends_on so Cloud SQL is not created until Private Services Access peering exists."
  value       = google_service_networking_connection.private_vpc_connection.id
}
