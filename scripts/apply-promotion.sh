#!/bin/bash
#
# Manual promotion wrapper for applying Terraform to a target environment.
# Designed for operator use outside the CI/CD pipeline (e.g., emergency hotfix).
# Requires confirmation prompts before applying.
#
# Usage:
#   export GITLAB_TOKEN=glpat-xxxxxxxxxxxx
#   ./apply-promotion.sh qa \
#       http://vault.internal:8200 \
#       $VAULT_ROLE_ID \
#       $VAULT_SECRET_ID \
#       https://gitlab.internal \
#       42

set -euo pipefail

ENVIRONMENT="${1:-}"
VAULT_ADDR="${2:-}"
VAULT_ROLE_ID="${3:-}"
VAULT_SECRET_ID="${4:-}"
GITLAB_URL="${5:-${GITLAB_URL:-}}"
GITLAB_PROJECT_ID="${6:-${GITLAB_PROJECT_ID:-}}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"

if [[ ! "$ENVIRONMENT" =~ ^(dev|qa|uat|prod)$ ]]; then
    echo "ERROR: Invalid environment. Must be dev, qa, uat, or prod."
    exit 1
fi

if [[ -z "$VAULT_ADDR" || -z "$VAULT_ROLE_ID" || -z "$VAULT_SECRET_ID" ]]; then
    echo "ERROR: Missing Vault arguments."
    echo "Usage: $0 <env> <vault-addr> <vault-role-id> <vault-secret-id> [gitlab-url] [gitlab-project-id]"
    exit 1
fi

if [[ -z "$GITLAB_URL" || -z "$GITLAB_PROJECT_ID" || -z "$GITLAB_TOKEN" ]]; then
    echo "ERROR: GitLab credentials required. Set GITLAB_URL, GITLAB_PROJECT_ID, and GITLAB_TOKEN."
    exit 1
fi

TERRAFORM_ROOT="$(cd "$(dirname "$0")/../terraform" && pwd)"
VAR_FILE="$TERRAFORM_ROOT/../environments/$ENVIRONMENT.tfvars"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

STATE_BASE="$GITLAB_URL/api/v4/projects/$GITLAB_PROJECT_ID/terraform/state"
STATE_ADDRESS="$STATE_BASE/pingone-$ENVIRONMENT"

# ---------------------------------------------------------------------------
# Confirmation prompts
# ---------------------------------------------------------------------------
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  MANUAL TERRAFORM PROMOTION                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Environment:  $ENVIRONMENT"
echo "State:        $STATE_ADDRESS"
echo ""
echo "⚠ This is a MANUAL promotion — NOT triggered via GitLab CI/CD pipeline."
echo ""

read -p "Type the environment name to confirm ($ENVIRONMENT): " CONFIRM
if [[ "$CONFIRM" != "$ENVIRONMENT" ]]; then
    echo "Confirmation did not match. Aborting."
    exit 0
fi

# ---------------------------------------------------------------------------
# Fetch secrets
# ---------------------------------------------------------------------------
echo ""
echo "Fetching secrets..."
# shellcheck source=/dev/null
source "$SCRIPT_DIR/fetch-secrets.sh" "$ENVIRONMENT" "$VAULT_ADDR" "$VAULT_ROLE_ID" "$VAULT_SECRET_ID"

# ---------------------------------------------------------------------------
# Init with GitLab state backend
# ---------------------------------------------------------------------------
cd "$TERRAFORM_ROOT"

terraform init \
    -backend-config="address=$STATE_ADDRESS" \
    -backend-config="lock_address=$STATE_ADDRESS/lock" \
    -backend-config="unlock_address=$STATE_ADDRESS/lock" \
    -backend-config="username=gitlab-ci-token" \
    -backend-config="password=$GITLAB_TOKEN" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5" \
    -input=false -reconfigure

echo ""
echo "Generating plan..."
terraform plan \
    -var-file="$VAR_FILE" \
    -out="manual-apply.tfplan" \
    -input=false

# ---------------------------------------------------------------------------
# Review and apply
# ---------------------------------------------------------------------------
echo ""
echo "⚠ Review the plan above."
read -p "Apply this plan to $ENVIRONMENT? (yes/no): " APPLY_CONFIRM

if [[ "$APPLY_CONFIRM" != "yes" ]]; then
    echo "Apply cancelled."
    rm -f "manual-apply.tfplan"
    exit 0
fi

echo ""
echo "Applying changes to $ENVIRONMENT..."
terraform apply "manual-apply.tfplan"
rm -f "manual-apply.tfplan"

echo ""
echo "✓ Manual apply to $ENVIRONMENT complete."
