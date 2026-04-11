output "enabled_apis" {
  description = "List of API service names this module enabled. Other modules use this as a depends_on anchor: `depends_on = [module.apis.enabled_apis]` ensures the APIs are enabled before resources are created."
  value       = [for s in google_project_service.this : s.service]
}
