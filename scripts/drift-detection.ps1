<#
.SYNOPSIS
    Run Terraform drift detection for a given environment using GitLab-managed state.
    Exits with code 1 if drift is detected (pipeline can treat as warning or failure).

.PARAMETER Environment
    Target environment: dev | qa | uat | prod

.NOTES
    Reads the following environment variables for GitLab state authentication.
    In the CI pipeline these are set automatically:
        CI_API_V4_URL    — GitLab API base URL
        CI_PROJECT_ID    — numeric project ID
        CI_JOB_TOKEN     — short-lived job token (auto-set by GitLab)

    For manual runs outside the pipeline, set:
        GITLAB_URL       — e.g. https://gitlab.internal
        GITLAB_PROJECT_ID
        GITLAB_TOKEN     — Personal Access Token with api scope

.EXAMPLE
    # In pipeline: env vars are already set, just call:
    .\drift-detection.ps1 -Environment prod
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "qa", "uat", "prod")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"
$TerraformRoot = Join-Path $PSScriptRoot "..\terraform"
$VarFile       = Join-Path $PSScriptRoot "..\environments\$Environment.tfvars"

# Resolve GitLab state credentials — pipeline vars take priority
$gitlabUrl  = if ($env:CI_API_V4_URL)    { $env:CI_API_V4_URL }    else { "$env:GITLAB_URL/api/v4" }
$projectId  = if ($env:CI_PROJECT_ID)    { $env:CI_PROJECT_ID }    else { $env:GITLAB_PROJECT_ID }
$stateToken = if ($env:CI_JOB_TOKEN)     { $env:CI_JOB_TOKEN }     else { $env:GITLAB_TOKEN }

if (-not $gitlabUrl -or -not $projectId -or -not $stateToken) {
    Write-Error "GitLab state credentials not set. In pipeline CI_API_V4_URL/CI_PROJECT_ID/CI_JOB_TOKEN are automatic. Outside the pipeline set GITLAB_URL, GITLAB_PROJECT_ID, GITLAB_TOKEN."
    exit 1
}

# Confirm PingOne env vars are set (set by fetch-secrets.ps1 earlier in the job)
if (-not $env:TF_VAR_pingone_client_id) {
    Write-Error "TF_VAR_pingone_client_id is not set. Run fetch-secrets.ps1 first."
    exit 1
}

$stateBase = "$gitlabUrl/projects/$projectId/terraform/state"

Set-Location $TerraformRoot

Write-Host "Initialising Terraform for drift check ($Environment)..."
terraform init `
    -backend-config="address=$stateBase/pingone-$Environment" `
    -backend-config="lock_address=$stateBase/pingone-$Environment/lock" `
    -backend-config="unlock_address=$stateBase/pingone-$Environment/lock" `
    -backend-config="username=gitlab-ci-token" `
    -backend-config="password=$stateToken" `
    -backend-config="lock_method=POST" `
    -backend-config="unlock_method=DELETE" `
    -backend-config="retry_wait_min=5" `
    -input=false -reconfigure | Out-Default

Write-Host "Running terraform plan with -detailed-exitcode..."

# -detailed-exitcode: 0=no changes, 1=error, 2=changes detected
terraform plan `
    -var-file="$VarFile" `
    -input=false `
    -lock=false `
    -detailed-exitcode | Out-Default

$exitCode = $LASTEXITCODE

switch ($exitCode) {
    0 {
        Write-Host "No drift detected — infrastructure matches configuration for $Environment."
        exit 0
    }
    2 {
        Write-Warning "DRIFT DETECTED in $Environment — infrastructure has diverged from Terraform config."
        Write-Warning "Review the plan output above and apply or investigate."
        exit 1
    }
    default {
        Write-Error "Terraform plan failed with exit code $exitCode for $Environment."
        exit 1
    }
}
