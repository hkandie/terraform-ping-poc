# =============================================================================
# Module: authentication
# Manages PingOne sign-on policies, sign-on policy actions, and password policy.
# =============================================================================

resource "pingone_password_policy" "main" {
  environment_id = var.environment_id
  name           = "${var.environment_name}-password-policy"
  description    = "Password policy for ${var.environment_name}. Managed by Terraform."
  length = {
    min = 15
    max = 64
  }

  min_characters = {
    alphabetical_uppercase = 0
    alphabetical_lowercase = 1
    numeric                = 1
    special_characters     = 1
  }

  lockout = {
    duration_seconds = 900
    failure_count    = 5
  }
}

resource "pingone_sign_on_policy" "main" {
  environment_id = var.environment_id
  name           = "${var.environment_name}-sign-on-policy"
  description    = "Sign-on policy for ${var.environment_name}. Managed by Terraform."
}

# Login action — always required
resource "pingone_sign_on_policy_action" "login" {
  environment_id    = var.environment_id
  sign_on_policy_id = pingone_sign_on_policy.main.id
  priority          = 1

  login {
    recovery_enabled = true
  }
}

# MFA action — enforced when mfa_required = true
resource "pingone_sign_on_policy_action" "mfa" {
  count = var.mfa_required ? 1 : 0

  environment_id    = var.environment_id
  sign_on_policy_id = pingone_sign_on_policy.main.id
  priority          = 2

  mfa {
    device_sign_on_policy_id = var.environment_id # overridden by mfa module output if needed
    no_device_mode           = "BYPASS"
  }
}
