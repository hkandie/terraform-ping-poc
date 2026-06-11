output "application_ids" {
  description = "Map of logical application name to PingOne application ID."
  value       = { for k, v in pingone_application.apps : k => v.id }
}
