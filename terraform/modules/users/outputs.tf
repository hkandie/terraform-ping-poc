output "default_population_id" {
  description = "ID of the default user population."
  value       = pingone_population.default.id
}

output "admins_population_id" {
  description = "ID of the administrators population."
  value       = pingone_population.admins.id
}
