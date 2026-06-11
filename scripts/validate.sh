#!/bin/bash
#
# Pre-apply validation: checks format, validates, and performs a plan dry-run.
# Intended for local developer use before pushing to GitLab.
#
# Usage:
#   ./validate.sh dev

set -euo pipefail

ENVIRONMENT="${1:-}"

if [[ ! "$ENVIRONMENT" =~ ^(dev|qa|uat|prod)$ ]]; then
    echo "ERROR: Invalid environment. Must be dev, qa, uat, or prod."
    exit 1
fi

TERRAFORM_ROOT="$(cd "$(dirname "$0")/../terraform" && pwd)"
VAR_FILE="$(cd "$(dirname "$0")/../environments" && pwd)/$ENVIRONMENT.tfvars"

PASS_COUNT=0
FAIL_COUNT=0

run_check() {
    local name="$1"
    local cmd="$2"
    echo ""
    echo "--- $name ---"
    if eval "$cmd"; then
        echo "✓ PASS: $name"
        ((PASS_COUNT++))
    else
        echo "✗ FAIL: $name"
        ((FAIL_COUNT++))
    fi
}

cd "$TERRAFORM_ROOT"

run_check "Terraform Format" "terraform fmt -check -recursive -diff"
run_check "Terraform Init (no backend)" "terraform init -backend=false -input=false"
run_check "Terraform Validate" "terraform validate"

echo ""
echo "========================================="
echo "Validation Summary:"
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo "========================================="

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
