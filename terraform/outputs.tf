output "sign_on_policy_id" {
  description = "ID of the sign-on policy created by the authentication module."
  value       = module.authentication.sign_on_policy_id
}

output "password_policy_id" {
  description = "ID of the password policy created by the authentication module."
  value       = module.authentication.password_policy_id
}

output "default_population_id" {
  description = "ID of the default user population."
  value       = module.users.default_population_id
}

output "application_ids" {
  description = "Map of logical application name to PingOne application ID."
  value       = module.applications.application_ids
}

output "mfa_policy_id" {
  description = "ID of the MFA device policy."
  value       = module.mfa.mfa_policy_id
}
