environment_name    = "production"
pingone_region_code = "NA"

auth_policies = {
  mfa_required    = true
  session_timeout = 3600 # 1 hour
  password_policy = {
    min_length      = 12
    require_numbers = true
    require_symbols = true
    expiration_days = 90
  }
}

applications = {
  "web-app-prod" = {
    name    = "Production Web Application"
    type    = "WEB_APP"
    sign_on = "OIDC"
  }
  "api-app-prod" = {
    name    = "Production API"
    type    = "SERVICE"
    sign_on = "CLIENT_CREDENTIALS"
  }
}

users = {
  environment_admins = 10
  operators          = 20
  qa_testers         = 0
}

mfa_policies = {
  sms_enabled  = true
  otp_enabled  = true
  push_enabled = true
  duo_enabled  = true # additional layer for prod
}

tags = {
  Environment   = "production"
  ManagedBy     = "Terraform"
  CriticalInfra = "true"
  Owner         = "Security-Team"
}
