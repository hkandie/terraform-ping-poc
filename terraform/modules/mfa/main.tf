# =============================================================================
# Module: mfa
# Manages PingOne MFA device policy controlling which second factors are allowed.
# =============================================================================

resource "pingone_mfa_policy" "main" {
  environment_id = var.environment_id
  name           = "${var.environment_name}-mfa-policy"

  sms {
    enabled           = var.mfa_policies.sms_enabled
    pairing_disabled  = false
    otp_lifetime_unit = "MINUTES"
    otp_lifetime      = 5
  }

  totp {
    enabled          = var.mfa_policies.otp_enabled
    pairing_disabled = false
  }

  mobile {
    enabled          = var.mfa_policies.push_enabled
    pairing_disabled = false
    otp {
      failure {
        count          = 5
        cool_down_unit = "MINUTES"
        cool_down      = 5
      }
    }
    push {
      timeout_unit   = "MINUTES"
      timeout        = 2
      intent_enabled = false
    }
  }
}
