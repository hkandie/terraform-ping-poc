environment_name = "development"
pingone_region_code = "NA"

auth_policies = {
  mfa_required    = true
  session_timeout = 28800 # 8 hours
  password_policy = {
    min_length      = 8
    require_numbers = true
    require_symbols = false
    expiration_days = 0 # no expiry in dev
  }
}

applications = {
  "web-app-dev" = {
    name    = "Development Web Application"
    type    = "WEB_APP"
    sign_on = "OIDC"
  }
  "api-app-dev" = {
    name    = "Development API"
    type    = "SERVICE"
    sign_on = "CLIENT_CREDENTIALS"
  }
}

users = {
  environment_admins = 5
  qa_testers         = 10
  operators          = 0
}

mfa_policies = {
  sms_enabled  = true
  otp_enabled  = true
  push_enabled = true
  duo_enabled  = false
}

tags = {
  Environment = "dev"
  ManagedBy   = "Terraform"
  Owner       = "Platform-Team"
}
