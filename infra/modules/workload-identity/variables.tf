variable "project_id" {
  type        = string
  description = "GCP project ID where the WIF pool, provider, and service account live."
}

variable "github_repository" {
  type        = string
  description = "GitHub repository slug allowed to authenticate via WIF (e.g. 'owner/paperclip-greeteat'). The OIDC provider's attribute_condition restricts token exchange to assertions where assertion.repository matches this exactly. **Set this in terraform.tfvars before the first terraform apply.**"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in 'owner/repo' format (e.g. 'paperclipai/paperclip-greeteat')."
  }
}
