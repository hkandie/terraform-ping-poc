# =============================================================================
# PingOne API credentials — injected via TF_VAR_* from fetch-secrets.ps1
# =============================================================================

variable "pingone_client_id" {
  description = "PingOne Worker App Client ID (injected from vault at pipeline runtime)."
  type        = string
  sensitive   = true
}

variable "pingone_client_secret" {
  description = "PingOne Worker App Client Secret (injected from vault at pipeline runtime)."
  type        = string
  sensitive   = true
}

variable "pingone_environment_id" {
  description = "PingOne Environment ID that Terraform will manage resources within."
  type        = string
  sensitive   = true
}

variable "pingone_region_code" {
  description = "PingOne region code: NA (North America), EU (Europe), AP (Asia-Pacific), CA (Canada)."
  type        = string
  default     = "NA"
}

# =============================================================================
# Environment-level variables (set per-environment via tfvars)
# =============================================================================

variable "environment_name" {
  description = "Human-readable environment name (e.g. development, production)."
  type        = string
}

variable "auth_policies" {
  description = "Authentication policy configuration block."
  type = object({
    mfa_required    = bool
    session_timeout = optional(number, 28800)
    password_policy = object({
      min_length      = number
      require_numbers = bool
      require_symbols = bool
      expiration_days = optional(number, 0)
    })
  })
}

variable "applications" {
  description = "Map of PingOne application definitions keyed by logical name."
  type = map(object({
    name    = string
    type    = string
    sign_on = string
  }))
  default = {}
}

variable "users" {
  description = "User population sizing per role."
  type = object({
    environment_admins = number
    operators          = optional(number, 0)
    qa_testers         = optional(number, 0)
  })
}

variable "mfa_policies" {
  description = "MFA device method configuration."
  type = object({
    sms_enabled  = bool
    otp_enabled  = bool
    push_enabled = bool
    duo_enabled  = optional(bool, false)
  })
}

variable "tags" {
  description = "Metadata tags applied to all managed resources where supported."
  type        = map(string)
  default     = {}
}
