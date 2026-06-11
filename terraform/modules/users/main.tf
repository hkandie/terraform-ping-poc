# =============================================================================
# Module: users
# Manages PingOne user populations (logical groupings for users and policies).
# Individual user accounts are provisioned via SCIM or manual import — not here.
# =============================================================================

resource "pingone_population" "default" {
  environment_id = var.environment_id
  name           = "${var.environment_name}-default"
  description    = "Default population for ${var.environment_name}. Managed by Terraform."
}

resource "pingone_population" "admins" {
  environment_id = var.environment_id
  name           = "${var.environment_name}-admins"
  description    = "Administrator population for ${var.environment_name} (${var.user_config.environment_admins} seats). Managed by Terraform."
}

resource "pingone_population" "operators" {
  count = var.user_config.operators > 0 ? 1 : 0

  environment_id = var.environment_id
  name           = "${var.environment_name}-operators"
  description    = "Operator population for ${var.environment_name} (${var.user_config.operators} seats). Managed by Terraform."
}

resource "pingone_population" "qa_testers" {
  count = var.user_config.qa_testers > 0 ? 1 : 0

  environment_id = var.environment_id
  name           = "${var.environment_name}-qa-testers"
  description    = "QA tester population for ${var.environment_name} (${var.user_config.qa_testers} seats). Managed by Terraform."
}
