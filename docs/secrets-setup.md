# Secrets Setup — HashiCorp Vault AppRole Integration

## Overview

The pipeline uses Vault's **AppRole** auth method instead of long-lived tokens:

- The **Role ID** is non-sensitive (like a username) — stored as a plain GitLab CI Variable
- The **Secret ID** is sensitive (like a password) — stored as a masked GitLab CI Variable
- Both are injected into the pipeline job as `VAULT_ROLE_ID` and `VAULT_SECRET_ID`
- `fetch-secrets.ps1` exchanges these for a **short-lived Vault token** (5 min TTL), reads the secret, then immediately **revokes the token**

This means a leaked job log cannot be used to access Vault after the job completes.

---

## Step-by-Step Setup

### 1. Enable KV v2 secrets engine

```bash
vault secrets enable -path=secret kv-v2
```

### 2. Store PingOne credentials

```bash
vault kv put secret/pingone/dev \
  client_id="<worker-app-client-id-for-dev>" \
  client_secret="<worker-app-client-secret-for-dev>" \
  environment_id="<pingone-environment-id-for-dev>"

vault kv put secret/pingone/qa  client_id="..." client_secret="..." environment_id="..."
vault kv put secret/pingone/uat client_id="..." client_secret="..." environment_id="..."
vault kv put secret/pingone/prod client_id="..." client_secret="..." environment_id="..."
```

### 3. Create Vault policy

Save as `pingone-reader.hcl`:
```hcl
# Read PingOne secrets for any environment
path "secret/data/pingone/*" {
  capabilities = ["read"]
}

# Allow token self-revocation after use
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
```

```bash
vault policy write pingone-reader pingone-reader.hcl
```

### 4. Enable AppRole auth

```bash
vault auth enable approle
```

### 5. Create AppRole role

```bash
vault write auth/approle/role/gitlab-runner \
  token_policies="pingone-reader" \
  token_ttl=5m \
  token_max_ttl=10m \
  secret_id_ttl=0        # Non-expiring Secret ID (rotate manually quarterly)
```

### 6. Get Role ID and Secret ID

```bash
# Role ID (non-sensitive, use as VAULT_ROLE_ID in GitLab)
vault read auth/approle/role/gitlab-runner/role-id

# Secret ID (sensitive, use as VAULT_SECRET_ID in GitLab — masked)
vault write -f auth/approle/role/gitlab-runner/secret-id
```

### 7. Configure GitLab CI Variables

Navigate to: **GitLab project → Settings → CI/CD → Variables → Add variable**

| Key | Value | Protected | Masked |
|---|---|---|---|
| `VAULT_ROLE_ID` | `<role-id from above>` | No | No |
| `VAULT_SECRET_ID` | `<secret-id from above>` | Yes | Yes |

---

## Rotating the Secret ID

```bash
# Generate a new Secret ID
vault write -f auth/approle/role/gitlab-runner/secret-id

# Update the GitLab CI Variable VAULT_SECRET_ID with the new value
# The old Secret ID can optionally be revoked:
vault write auth/approle/role/gitlab-runner/secret-id-accessor/destroy \
  secret_id_accessor="<old-accessor>"
```

Rotate quarterly (minimum) or immediately if a pipeline log is inadvertently shared.

---

## Verifying the Setup

```powershell
# Test AppRole login from the runner machine
$body = '{"role_id":"<role-id>","secret_id":"<secret-id>"}'
$resp = Invoke-RestMethod -Uri "http://vault.internal:8200/v1/auth/approle/login" `
  -Method POST -ContentType "application/json" -Body $body
$token = $resp.auth.client_token

# Read the dev secret
Invoke-RestMethod -Uri "http://vault.internal:8200/v1/secret/data/pingone/dev" `
  -Headers @{"X-Vault-Token"=$token}

# Revoke the token
Invoke-RestMethod -Uri "http://vault.internal:8200/v1/auth/token/revoke-self" `
  -Method POST -Headers @{"X-Vault-Token"=$token}
```
