<#
.SYNOPSIS
    Pre-apply validation: checks format, validates, and performs a plan dry-run.
    Intended for local developer use before pushing to GitLab.

.PARAMETER Environment
    Target environment: dev | qa | uat | prod

.EXAMPLE
    .\validate.ps1 -Environment dev
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "qa", "uat", "prod")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"
$TerraformRoot = Join-Path $PSScriptRoot "..\terraform"
$VarFile       = Join-Path $PSScriptRoot "..\environments\$Environment.tfvars"
$PassCount     = 0
$FailCount     = 0

function Invoke-Check {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "`n--- $Name ---"
    try {
        & $Action
        Write-Host "PASS: $Name"
        $script:PassCount++
    } catch {
        Write-Warning "FAIL: $Name — $($_.Exception.Message)"
        $script:FailCount++
    }
}

Set-Location $TerraformRoot

Invoke-Check "Terraform Format" {
    terraform fmt -check -recursive -diff
}

Invoke-Check "Terraform Init (no backend)" {
    terraform init -backend=false -input=false
}

Invoke-Check "Terraform Validate" {
    terraform validate
}

Invoke-Check "TFLint" {
    $tflintConfig = Join-Path $PSScriptRoot "..\.tflint.hcl"
    tflint --init --config="$tflintConfig"
    tflint --config="$tflintConfig" --format compact
}

Write-Host "`n=============================="
Write-Host "Validation Summary: $PassCount passed, $FailCount failed"
Write-Host "=============================="

if ($FailCount -gt 0) {
    Write-Error "$FailCount check(s) failed. Fix issues before pushing."
    exit 1
}

Write-Host "All checks passed for environment: $Environment"
