#!/bin/bash
#
# Runner Health Check — validates connectivity to on-premises dependencies
# (Vault, PingOne API, DNS resolution, network reachability)
#
# Usage:
#   ./health-check.sh
#   VAULT_ADDR=http://vault.internal:8200 ./health-check.sh
#

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://vault.internal:8200}"
VAULT_HOST=$(echo "$VAULT_ADDR" | sed -E 's|^https?://([^:]+).*|\1|')
VAULT_PORT=$(echo "$VAULT_ADDR" | grep -oE ':[0-9]+$' | sed 's/:// ' || echo "8200")

PING_REGION="${PING_REGION:-com}"
PING_API="api.pingone.com"

PASS_COUNT=0
FAIL_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

check() {
    local name="$1"
    local cmd="$2"
    echo -n "  [*] $name... "
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((FAIL_COUNT++))
    fi
}

info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  GitLab Runner Health Check                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ---------------------------------------------------------------------------
# System checks
# ---------------------------------------------------------------------------
echo "System & Tools:"
check "Bash version" "bash --version | grep -q bash"
check "curl installed" "which curl"
check "jq installed" "which jq"
check "git installed" "which git"
check "terraform installed" "which terraform"

# ---------------------------------------------------------------------------
# DNS Resolution
# ---------------------------------------------------------------------------
echo ""
echo "DNS Resolution:"
check "Vault host resolves ($VAULT_HOST)" "nslookup $VAULT_HOST"
check "PingOne API resolves ($PING_API)" "nslookup $PING_API"
check "GitLab instance resolves" "nslookup $(echo ${CI_SERVER_HOST:-gitlab.internal})"

# ---------------------------------------------------------------------------
# Network Connectivity
# ---------------------------------------------------------------------------
echo ""
echo "Network Connectivity:"
check "Vault HTTP accessible" "curl -s -o /dev/null -w '%{http_code}' http://$VAULT_HOST:${VAULT_PORT} | grep -qE '^(200|400|403|404|500)'"
check "PingOne API HTTPS accessible" "curl -s -o /dev/null -w '%{http_code}' https://$PING_API/v1/health | grep -q ."

# ---------------------------------------------------------------------------
# Vault Health
# ---------------------------------------------------------------------------
echo ""
echo "Vault Health:"
VAULT_HEALTH=$(curl -s "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo '{}')
check "Vault service responding" "[[ -n \"$VAULT_HEALTH\" ]]"

VAULT_SEALED=$(echo "$VAULT_HEALTH" | jq -r '.sealed // "unknown"' 2>/dev/null || echo "unknown")
if [[ "$VAULT_SEALED" == "false" ]]; then
    info "Vault is unsealed and operational"
    ((PASS_COUNT++))
elif [[ "$VAULT_SEALED" == "true" ]]; then
    echo -e "  ${RED}✗ FAIL${NC} Vault is SEALED — cannot fetch secrets"
    ((FAIL_COUNT++))
else
    info "Vault status unknown (may be in init/migration mode)"
fi

# ---------------------------------------------------------------------------
# Vault AppRole (if credentials provided)
# ---------------------------------------------------------------------------
echo ""
echo "Vault AppRole Authentication:"
if [[ -n "${VAULT_ROLE_ID:-}" && -n "${VAULT_SECRET_ID:-}" ]]; then
    check "AppRole login" "curl -s -X POST -H 'Content-Type: application/json' -d '{\"role_id\": \"'$VAULT_ROLE_ID'\", \"secret_id\": \"'$VAULT_SECRET_ID'\"}' $VAULT_ADDR/v1/auth/approle/login | jq -e '.auth.client_token' > /dev/null"
    info "AppRole credentials are valid"
else
    info "VAULT_ROLE_ID or VAULT_SECRET_ID not set — skipping AppRole test"
fi

# ---------------------------------------------------------------------------
# GitLab Runner Environment
# ---------------------------------------------------------------------------
echo ""
echo "GitLab Runner Environment:"
check "CI_PROJECT_DIR set" "[[ -n \"\${CI_PROJECT_DIR:-}\" ]]"
check "CI_COMMIT_SHA set" "[[ -n \"\${CI_COMMIT_SHA:-}\" ]]"
if [[ -n "${CI_PROJECT_DIR:-}" ]]; then
    check "terraform/ directory exists" "[[ -d \"$CI_PROJECT_DIR/terraform\" ]]"
    check "scripts/ directory exists" "[[ -d \"$CI_PROJECT_DIR/scripts\" ]]"
    check "environments/ directory exists" "[[ -d \"$CI_PROJECT_DIR/environments\" ]]"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════"
echo "Health Check Summary:"
echo -e "  ${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "  ${RED}FAIL: $FAIL_COUNT${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}✗ Health check FAILED — see errors above${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Health check PASSED — runner is healthy${NC}"
    exit 0
fi
