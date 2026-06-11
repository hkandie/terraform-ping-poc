variable "environment_id" {
  description = "PingOne environment ID."
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Human-readable environment label used in resource names."
  type        = string
}

variable "applications" {
  description = "Map of application definitions keyed by logical name."
  type = map(object({
    name    = string
    type    = string # WEB_APP | NATIVE_APP | SERVICE | SINGLE_PAGE_APP
    sign_on = string # OIDC | SAML | CLIENT_CREDENTIALS
  }))
  default = {}
}

variable "tags" {
  description = "Metadata tags."
  type        = map(string)
  default     = {}
}
