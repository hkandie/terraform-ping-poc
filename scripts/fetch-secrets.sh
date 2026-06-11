#!/bin/bash
#
# Fetch PingOne API credentials from HashiCorp Vault using AppRole authentication
# and export them as TF_VAR_* environment variables for Terraform.
#
# Usage:
#   ./fetch-secrets.sh dev http://vault.internal:8200 $VAULT_ROLE_ID $VAULT_SECRET_ID
#
# Environment variables exported:
#   TF_VAR_pingone_client_id
#   TF_VAR_pingone_client_secret
#   TF_VAR_pingone_environment_id

set -euo pipefail

ENVIRONMENT="${1:-}"
VAULT_ADDR="${2:-}"
VAULT_ROLE_ID="${3:-}"
VAULT_SECRET_ID="${4:-}"

# Validation
if [[ ! "$ENVIRONMENT" =~ ^(dev|qa|uat|prod)$ ]]; then
    echo "ERROR: Invalid environment. Must be dev, qa, uat, or prod."
    exit 1
fi

if [[ -z "$VAULT_ADDR" || -z "$VAULT_ROLE_ID" || -z "$VAULT_SECRET_ID" ]]; then
    echo "ERROR: Missing required arguments."
    echo "Usage: $0 <environment> <vault-addr> <vault-role-id> <vault-secret-id>"
    exit 1
fi

# Validate Vault address format
if ! [[ "$VAULT_ADDR" =~ ^https?://[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]; then
    echo "ERROR: VAULT_ADDR does not match expected format (http/https://host[:port])"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Authenticate with Vault via AppRole
# ---------------------------------------------------------------------------
echo "Authenticating with Vault via AppRole..."

LOGIN_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"role_id\": \"$VAULT_ROLE_ID\", \"secret_id\": \"$VAULT_SECRET_ID\"}" \
    "$VAULT_ADDR/v1/auth/approle/login")

VAULT_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"client_token":"[^"]*' | cut -d'"' -f4)

if [[ -z "$VAULT_TOKEN" ]]; then
    echo "ERROR: Vault AppRole login failed. Check credentials and Vault connectivity."
    echo "$LOGIN_RESPONSE" | jq . 2>/dev/null || echo "$LOGIN_RESPONSE"
    exit 1
fi

echo "Vault authentication successful."

# ---------------------------------------------------------------------------
# Step 2: Fetch PingOne credentials from kv-v2 secret path
# ---------------------------------------------------------------------------
SECRET_PATH="secret/data/pingone/$ENVIRONMENT"

SECRET_RESPONSE=$(curl -s -X GET \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/$SECRET_PATH")

# Extract credentials
CLIENT_ID=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.client_id // empty')
CLIENT_SECRET=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.client_secret // empty')
ENVIRONMENT_ID=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.environment_id // empty')

# Revoke the token immediately after use (best effort)
curl -s -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/auth/token/revoke-self" &>/dev/null || true

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$ENVIRONMENT_ID" ]]; then
    echo "ERROR: Vault secret at $SECRET_PATH is missing required keys: client_id, client_secret, environment_id"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Export as TF_VAR_* environment variables
# ---------------------------------------------------------------------------
export TF_VAR_pingone_client_id="$CLIENT_ID"
export TF_VAR_pingone_client_secret="$CLIENT_SECRET"
export TF_VAR_pingone_environment_id="$ENVIRONMENT_ID"

echo "Secrets loaded for environment: $ENVIRONMENT"
