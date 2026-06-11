terraform {
  required_version = ">= 1.5.0"

  required_providers {
    pingone = {
      source  = "pingidentity/pingone"
      version = "~> 1.0"
    }
  }
}

# PingOne Provider — credentials injected via TF_VAR_* env vars by fetch-secrets.ps1
provider "pingone" {
  client_id      = var.pingone_client_id
  client_secret  = var.pingone_client_secret
  environment_id = var.pingone_environment_id
  region_code    = var.pingone_region_code
}
