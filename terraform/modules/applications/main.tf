# =============================================================================
# Module: applications
# Manages PingOne OIDC applications. SAML apps follow the same pattern using
# the pingone_application resource with a saml{} block instead.
# =============================================================================

resource "pingone_application" "apps" {
  for_each = var.applications

  environment_id = var.environment_id
  name           = each.value.name
  enabled        = true


}
