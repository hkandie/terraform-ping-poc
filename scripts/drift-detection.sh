#!/bin/bash
#
# Run Terraform drift detection for a given environment using GitLab-managed state.
# Exits with code 1 if drift is detected (pipeline can treat as warning or failure).
#
# Usage (in pipeline):
#   ./drift-detection.sh prod
#
# Usage (manual):
#   GITLAB_URL=https://gitlab.internal GITLAB_PROJECT_ID=42 GITLAB_TOKEN=glpat-xxx \
#   ./drift-detection.sh prod

set -euo pipefail

ENVIRONMENT="${1:-}"

if [[ ! "$ENVIRONMENT" =~ ^(dev|qa|uat|prod)$ ]]; then
    echo "ERROR: Invalid environment. Must be dev, qa, uat, or prod."
    exit 1
fi

TERRAFORM_ROOT="$(cd "$(dirname "$0")/../terraform" && pwd)"
VAR_FILE="$(cd "$(dirname "$0")/../environments" && pwd)/$ENVIRONMENT.tfvars"

# Resolve GitLab state credentials — pipeline vars take priority
GITLAB_URL="${CI_API_V4_URL:-${GITLAB_URL:-}}"
PROJECT_ID="${CI_PROJECT_ID:-${GITLAB_PROJECT_ID:-}}"
STATE_TOKEN="${CI_JOB_TOKEN:-${GITLAB_TOKEN:-}}"

if [[ -z "$GITLAB_URL" || -z "$PROJECT_ID" || -z "$STATE_TOKEN" ]]; then
    echo "ERROR: GitLab state credentials not set."
    echo "In pipeline: CI_API_V4_URL, CI_PROJECT_ID, CI_JOB_TOKEN are automatic."
    echo "Manual: Set GITLAB_URL, GITLAB_PROJECT_ID, GITLAB_TOKEN."
    exit 1
fi

# Confirm PingOne env vars are set (set by fetch-secrets.sh earlier in the job)
if [[ -z "${TF_VAR_pingone_client_id:-}" ]]; then
    echo "ERROR: TF_VAR_pingone_client_id is not set. Run fetch-secrets.sh first."
    exit 1
fi

STATE_BASE="$GITLAB_URL/projects/$PROJECT_ID/terraform/state"

cd "$TERRAFORM_ROOT"

echo "Initialising Terraform for drift check ($ENVIRONMENT)..."
terraform init \
    -backend-config="address=$STATE_BASE/pingone-$ENVIRONMENT" \
    -backend-config="lock_address=$STATE_BASE/pingone-$ENVIRONMENT/lock" \
    -backend-config="unlock_address=$STATE_BASE/pingone-$ENVIRONMENT/lock" \
    -backend-config="username=gitlab-ci-token" \
    -backend-config="password=$STATE_TOKEN" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5" \
    -input=false -reconfigure

echo "Running terraform plan with -detailed-exitcode..."

# -detailed-exitcode: 0=no changes, 1=error, 2=changes detected
terraform plan \
    -var-file="$VAR_FILE" \
    -input=false \
    -lock=false \
    -detailed-exitcode || EXIT_CODE=$?

EXIT_CODE="${EXIT_CODE:-0}"

case $EXIT_CODE in
    0)
        echo "✓ No drift detected — infrastructure matches configuration for $ENVIRONMENT."
        exit 0
        ;;
    2)
        echo "⚠ DRIFT DETECTED in $ENVIRONMENT — infrastructure has diverged from Terraform config."
        echo "Review the plan output above and apply or investigate."
        exit 1
        ;;
    *)
        echo "✗ Terraform plan failed with exit code $EXIT_CODE for $ENVIRONMENT."
        exit 1
        ;;
esac
