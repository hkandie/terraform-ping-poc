# GitLab-managed Terraform state backend (HTTP backend with native locking).
#
# State is stored in GitLab's built-in Terraform state registry — no shared
# network drive or external object store required.
#
# All connection details (address, credentials) are injected via -backend-config
# in CI/CD using the auto-generated CI_JOB_TOKEN. State names follow the
# convention: pingone-<environment>  (e.g. pingone-dev, pingone-prod)
#
# For manual runs outside the pipeline, use a GitLab Personal Access Token
# with api scope — see scripts/apply-promotion.ps1 and docs/secrets-setup.md.
#
# GitLab docs: https://docs.gitlab.com/ee/user/infrastructure/iac/terraform_state.html

terraform {
  backend "http" {}
}
