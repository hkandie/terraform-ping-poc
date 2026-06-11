variable "environment_id" {
  description = "PingOne environment ID to create authentication resources in."
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Human-readable environment label used in resource names."
  type        = string
}

variable "mfa_required" {
  description = "Whether MFA is required in the sign-on policy."
  type        = bool
  default     = true
}

variable "session_timeout" {
  description = "Session idle timeout in seconds."
  type        = number
  default     = 28800
}

variable "password_policy" {
  description = "Password complexity and expiry settings."
  type = object({
    min_length      = number
    require_numbers = bool
    require_symbols = bool
    expiration_days = optional(number, 0)
  })
}

variable "tags" {
  description = "Metadata tags (informational — applied to descriptions where PingOne supports it)."
  type        = map(string)
  default     = {}
}
