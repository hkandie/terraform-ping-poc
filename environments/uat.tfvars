environment_name    = "uat"
pingone_region_code = "NA"

auth_policies = {
  mfa_required    = true
  session_timeout = 7200 # 2 hours — closer to prod behaviour
  password_policy = {
    min_length      = 12
    require_numbers = true
    require_symbols = true
    expiration_days = 0
  }
}

applications = {
  "web-app-uat" = {
    name    = "UAT Web Application"
    type    = "WEB_APP"
    sign_on = "OIDC"
  }
  "api-app-uat" = {
    name    = "UAT API"
    type    = "SERVICE"
    sign_on = "CLIENT_CREDENTIALS"
  }
}

users = {
  environment_admins = 5
  qa_testers         = 10
  operators          = 10
}

mfa_policies = {
  sms_enabled  = true
  otp_enabled  = true
  push_enabled = true
  duo_enabled  = false
}

tags = {
  Environment = "uat"
  ManagedBy   = "Terraform"
  Owner       = "Platform-Team"
}
