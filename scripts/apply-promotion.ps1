<#
.SYNOPSIS
    Manual promotion wrapper for applying Terraform to a target environment.
    Designed for operator use outside the CI/CD pipeline (e.g., emergency hotfix).
    Requires confirmation prompt before applying.

.PARAMETER Environment
    Target environment: dev | qa | uat | prod

.PARAMETER VaultAddr
    HashiCorp Vault address.

.PARAMETER VaultRoleId
    AppRole Role ID.

.PARAMETER VaultSecretId
    AppRole Secret ID.

.PARAMETER GitLabUrl
    GitLab instance base URL (e.g. https://gitlab.internal). Used to construct
    the Terraform state address. Defaults to $env:GITLAB_URL.

.PARAMETER GitLabProjectId
    GitLab numeric project ID. Defaults to $env:GITLAB_PROJECT_ID.

.PARAMETER GitLabToken
    GitLab Personal Access Token with api scope for state access.
    Defaults to $env:GITLAB_TOKEN. NEVER pass on the command line in shared
    environments — set the environment variable instead.

.EXAMPLE
    $env:GITLAB_TOKEN = "glpat-xxxxxxxxxxxx"
    .\apply-promotion.ps1 -Environment qa `
        -VaultAddr http://vault.internal:8200 `
        -VaultRoleId $env:VAULT_ROLE_ID `
        -VaultSecretId $env:VAULT_SECRET_ID `
        -GitLabUrl https://gitlab.internal `
        -GitLabProjectId 42
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
    [string]$VaultSecretId,

    [string]$GitLabUrl = $env:GITLAB_URL,

    [string]$GitLabProjectId = $env:GITLAB_PROJECT_ID,

    [string]$GitLabToken = $env:GITLAB_TOKEN
)

$ErrorActionPreference = "Stop"
$TerraformRoot = Join-Path $PSScriptRoot "..\terraform"
$VarFile       = Join-Path $PSScriptRoot "..\environments\$Environment.tfvars"

if (-not $GitLabUrl -or -not $GitLabProjectId -or -not $GitLabToken) {
    Write-Error "GitLab state credentials required. Set GITLAB_URL, GITLAB_PROJECT_ID, and GITLAB_TOKEN environment variables."
    exit 1
}

$stateBase    = "$GitLabUrl/api/v4/projects/$GitLabProjectId/terraform/state"
$stateAddress = "$stateBase/pingone-$Environment"

Write-Warning "You are about to apply Terraform changes to: $($Environment.ToUpper())"
Write-Warning "State: $stateAddress"
Write-Warning "This is a MANUAL promotion — not triggered via GitLab CI/CD pipeline."
$confirm = Read-Host "Type the environment name to confirm ($Environment)"

if ($confirm -ne $Environment) {
    Write-Host "Confirmation did not match. Aborting."
    exit 0
}

# Fetch secrets
Write-Host "Fetching secrets..."
& "$PSScriptRoot\fetch-secrets.ps1" `
    -Environment $Environment `
    -VaultAddr $VaultAddr `
    -VaultRoleId $VaultRoleId `
    -VaultSecretId $VaultSecretId

# Init with GitLab state backend
Set-Location $TerraformRoot

terraform init `
    -backend-config="address=$stateAddress" `
    -backend-config="lock_address=$stateAddress/lock" `
    -backend-config="unlock_address=$stateAddress/lock" `
    -backend-config="username=gitlab-ci-token" `
    -backend-config="password=$GitLabToken" `
    -backend-config="lock_method=POST" `
    -backend-config="unlock_method=DELETE" `
    -backend-config="retry_wait_min=5" `
    -input=false -reconfigure

terraform plan `
    -var-file="$VarFile" `
    -out="manual-apply.tfplan" `
    -input=false

Write-Warning "Review the plan above."
$applyConfirm = Read-Host "Apply this plan to $($Environment.ToUpper())? (yes/no)"

if ($applyConfirm -ne "yes") {
    Write-Host "Apply cancelled."
    Remove-Item -Force "manual-apply.tfplan" -ErrorAction SilentlyContinue
    exit 0
}

terraform apply "manual-apply.tfplan"
Remove-Item -Force "manual-apply.tfplan" -ErrorAction SilentlyContinue

Write-Host "Manual apply to $Environment complete."
