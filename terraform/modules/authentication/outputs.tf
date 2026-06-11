output "sign_on_policy_id" {
  description = "ID of the sign-on policy."
  value       = pingone_sign_on_policy.main.id
}

output "password_policy_id" {
  description = "ID of the password policy."
  value       = pingone_password_policy.main.id
}
