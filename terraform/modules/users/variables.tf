variable "environment_id" {
  description = "PingOne environment ID."
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Human-readable environment label used in resource names."
  type        = string
}

variable "user_config" {
  description = "Population sizing per user role."
  type = object({
    environment_admins = number
    operators          = optional(number, 0)
    qa_testers         = optional(number, 0)
  })
}

variable "tags" {
  description = "Metadata tags."
  type        = map(string)
  default     = {}
}
