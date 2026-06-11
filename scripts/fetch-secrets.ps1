<#
.SYNOPSIS
    Fetch PingOne API credentials from HashiCorp Vault using AppRole authentication
    and export them as TF_VAR_* environment variables for Terraform.

.DESCRIPTION
    Uses Vault AppRole auth method so the runner never needs a long-lived Vault token.
    The Role ID is non-sensitive (stored in GitLab CI Variable).
    The Secret ID is sensitive (stored in GitLab CI Variable, masked).

    Exports:
        TF_VAR_pingone_client_id
        TF_VAR_pingone_client_secret
        TF_VAR_pingone_environment_id

.PARAMETER Environment
    Target environment: dev | qa | uat | prod

.PARAMETER VaultAddr
    HashiCorp Vault address (e.g. http://vault.internal:8200)

.PARAMETER VaultRoleId
    AppRole Role ID — non-sensitive, injected from GitLab CI Variable VAULT_ROLE_ID.

.PARAMETER VaultSecretId
    AppRole Secret ID — sensitive, injected from GitLab CI Variable VAULT_SECRET_ID (masked).

.EXAMPLE
    .\fetch-secrets.ps1 -Environment dev -VaultAddr http://vault.internal:8200 `
        -VaultRoleId $env:VAULT_ROLE_ID -VaultSecretId $env:VAULT_SECRET_ID
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "qa", "uat", "prod")]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$VaultAddr,

    [Parameter(Mandatory = $true)]
    [string]$VaultRoleId,

    [Parameter(Mandatory = $true)]
    [string]$VaultSecretId
)

$ErrorActionPreference = "Stop"

# Validate inputs to prevent injection via env values
if ($VaultAddr -notmatch '^https?://[a-zA-Z0-9._\-]+(:\d+)?$') {
    Write-Error "VAULT_ADDR does not match expected format."
    exit 1
}

# ---------------------------------------------------------------------------
# Step 1: Authenticate with Vault via AppRole to obtain a short-lived token
# ---------------------------------------------------------------------------
Write-Host "Authenticating with Vault via AppRole..."

$loginBody = @{
    role_id   = $VaultRoleId
    secret_id = $VaultSecretId
} | ConvertTo-Json

try {
    $loginResponse = Invoke-RestMethod `
        -Uri "$VaultAddr/v1/auth/approle/login" `
        -Method POST `
        -ContentType "application/json" `
        -Body $loginBody
} catch {
    Write-Error "Vault AppRole login failed: $($_.Exception.Message)"
    exit 1
}

$vaultToken = $loginResponse.auth.client_token
if (-not $vaultToken) {
    Write-Error "No client_token returned from Vault login."
    exit 1
}

Write-Host "Vault authentication successful."

# ---------------------------------------------------------------------------
# Step 2: Fetch PingOne credentials from kv-v2 secret path
# ---------------------------------------------------------------------------
$secretPath = "secret/data/pingone/$Environment"

try {
    $secretResponse = Invoke-RestMethod `
        -Uri "$VaultAddr/v1/$secretPath" `
        -Method GET `
        -Headers @{ "X-Vault-Token" = $vaultToken }
} catch {
    Write-Error "Failed to fetch secret at $secretPath`: $($_.Exception.Message)"
    exit 1
} finally {
    # Revoke the short-lived token immediately after use
    try {
        Invoke-RestMethod `
            -Uri "$VaultAddr/v1/auth/token/revoke-self" `
            -Method POST `
            -Headers @{ "X-Vault-Token" = $vaultToken } | Out-Null
    } catch {
        Write-Warning "Could not revoke Vault token (non-fatal): $($_.Exception.Message)"
    }
}

$data = $secretResponse.data.data

if (-not $data.client_id -or -not $data.client_secret -or -not $data.environment_id) {
    Write-Error "Vault secret at $secretPath is missing one or more required keys: client_id, client_secret, environment_id"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 3: Export as TF_VAR_* environment variables
# NOTE: These are scoped to the current pipeline job process.
# ---------------------------------------------------------------------------
$env:TF_VAR_pingone_client_id      = $data.client_id
$env:TF_VAR_pingone_client_secret  = $data.client_secret
$env:TF_VAR_pingone_environment_id = $data.environment_id

Write-Host "Secrets loaded for environment: $Environment"
