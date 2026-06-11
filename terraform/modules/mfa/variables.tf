variable "environment_id" {
  description = "PingOne environment ID."
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Human-readable environment label used in resource names."
  type        = string
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
  description = "Metadata tags."
  type        = map(string)
  default     = {}
}
