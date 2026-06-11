environment_name    = "qa"
pingone_region_code = "NA"

auth_policies = {
  mfa_required    = true
  session_timeout = 14400 # 4 hours
  password_policy = {
    min_length      = 10
    require_numbers = true
    require_symbols = false
    expiration_days = 0
  }
}

applications = {
  "web-app-qa" = {
    name    = "QA Web Application"
    type    = "WEB_APP"
    sign_on = "OIDC"
  }
  "api-app-qa" = {
    name    = "QA API"
    type    = "SERVICE"
    sign_on = "CLIENT_CREDENTIALS"
  }
}

users = {
  environment_admins = 5
  qa_testers         = 15
  operators          = 5
}

mfa_policies = {
  sms_enabled  = true
  otp_enabled  = true
  push_enabled = true
  duo_enabled  = false
}

tags = {
  Environment = "qa"
  ManagedBy   = "Terraform"
  Owner       = "Platform-Team"
}
