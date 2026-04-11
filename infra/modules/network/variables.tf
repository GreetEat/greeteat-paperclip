variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region for the subnet and Serverless VPC Connector."
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR range for paperclip-subnet. Must be a /28 to satisfy the Serverless VPC Connector requirements."
  default     = "10.8.0.0/28"
}
