module "authentication" {
  source = "./modules/authentication"

  environment_id   = var.pingone_environment_id
  environment_name = var.environment_name
  password_policy  = var.auth_policies.password_policy
  mfa_required     = var.auth_policies.mfa_required
  session_timeout  = try(var.auth_policies.session_timeout, 28800)
  tags             = var.tags
}

module "users" {
  source = "./modules/users"

  environment_id   = var.pingone_environment_id
  environment_name = var.environment_name
  user_config      = var.users
  tags             = var.tags
}

module "applications" {
  source = "./modules/applications"

  environment_id   = var.pingone_environment_id
  environment_name = var.environment_name
  applications     = var.applications
  tags             = var.tags
}

module "mfa" {
  source = "./modules/mfa"

  environment_id   = var.pingone_environment_id
  environment_name = var.environment_name
  mfa_policies     = var.mfa_policies
  tags             = var.tags
}
