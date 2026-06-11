# GitLab IaC Pipeline for PingOne IDP Management
## Architecture & Implementation Plan

---

## 1. OVERVIEW

**Goal:** Manage PingOne IDP resources via Infrastructure-as-Code (Terraform) with GitLab CI/CD, deployed through Windows GitLab Runners to on-premises infrastructure.

**Key Constraints & Decisions:**
- Windows environment (on-premises)
- API credentials stored in on-premises secret vault (not GitLab secrets)
- Multi-environment deployment: dev → qa → uat → prod
- All IaC checks before apply: format, lint, plan validation
- Windows GitLab Runner handling pipeline execution

---

## 2. REPOSITORY STRUCTURE

```
pingone-idp-terraform/
├── .gitlab-ci.yml                 # CI/CD pipeline definition
├── .gitignore                      # Exclude state, creds, lock files
├── README.md                       # Project documentation
├── SETUP.md                        # Runner & secret vault setup
├── SIMULATION.md                   # Demo & testing scenarios
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── backend.tf                 # Remote state config
│   └── modules/
│       ├── authentication/
│       │   ├── main.tf            # PingOne auth policies
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── users/
│       │   ├── main.tf
│       │   └── variables.tf
│       ├── applications/
│       │   ├── main.tf
│       │   └── variables.tf
│       └── mfa/
│           ├── main.tf
│           └── variables.tf
├── environments/
│   ├── dev.tfvars
│   ├── qa.tfvars
│   ├── uat.tfvars
│   └── prod.tfvars
├── scripts/
│   ├── fetch-secrets.ps1          # PowerShell: retrieve API key from vault
│   ├── validate.ps1               # Custom validation
│   ├── apply-promotion.ps1        # Manual approval wrapper
│   └── drift-detection.ps1        # Check for config drift
└── docs/
    ├── architecture.md
    ├── runbook.md
    ├── troubleshooting.md
    └── secrets-setup.md
```

---

## 3. WINDOWS GITLAB RUNNER SETUP

### 3.1 Installation

**Prerequisites:**
- Windows Server 2016+ or Windows 10 Professional
- PowerShell 5.1+
- Git installed
- Terraform installed (`terraform.exe` in PATH)
- TFLint installed (optional, for linting)
- Network access to: GitLab instance, on-premises secret vault, PingOne API

**Steps:**

```powershell
# 1. Download GitLab Runner
$url = "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe"
Invoke-WebRequest -Uri $url -OutFile "C:\gitlab-runner\gitlab-runner.exe"

# 2. Register runner
cd "C:\gitlab-runner"
.\gitlab-runner.exe register `
  --url "https://your-gitlab-instance.com/" `
  --registration-token "YOUR_RUNNER_TOKEN" `
  --executor "shell" `
  --shell "powershell" `
  --description "Windows IaC Runner - PingOne" `
  --tag-list "windows,terraform,pingone" `
  --run-untagged "false"

# 3. Install as service
.\gitlab-runner.exe install --user "DOMAIN\svc-gitlab-runner" --password "SecurePassword123"

# 4. Start service
Start-Service gitlab-runner

# Verify
Get-Service gitlab-runner
```

### 3.2 Runner Configuration (`C:\GitLab-Runner\config.toml`)

```toml
[[runners]]
  name = "Windows IaC Runner"
  url = "https://your-gitlab-instance.com/"
  id = 1
  token = "glrt_xxxxxxxxxxxx"
  token_expiration_time = "2025-01-01T00:00:00Z"
  executor = "shell"
  shell = "powershell"
  [runners.machine]
  [runners.cache]
    [runners.cache.s3]
    [runners.cache.gcs]
```

---

## 4. SECRET MANAGEMENT: ON-PREMISES VAULT INTEGRATION

### 4.1 Supported Vaults
- **HashiCorp Vault** (recommended)
- **Windows Credential Manager** (lightweight)
- **Azure Key Vault** (if hybrid cloud)
- **Custom vault API**

### 4.2 Example: HashiCorp Vault Integration

**Vault Setup:**
```bash
# Store PingOne credentials in Vault
vault kv put secret/pingone/dev \
  client_id="your-client-id" \
  client_secret="your-client-secret" \
  environment_id="your-env-id"
```

**PowerShell Fetch Script (`scripts/fetch-secrets.ps1`):**
```powershell
param(
    [string]$Environment = "dev",
    [string]$VaultAddr = "http://vault.internal:8200",
    [string]$VaultToken = $env:VAULT_TOKEN
)

# Fetch from HashiCorp Vault
$headers = @{ "X-Vault-Token" = $VaultToken }
$secretPath = "secret/data/pingone/$Environment"

$response = Invoke-WebRequest `
  -Uri "$VaultAddr/v1/$secretPath" `
  -Headers $headers

$secret = $response.Content | ConvertFrom-Json
$data = $secret.data.data

# Export as environment variables for Terraform
$env:TF_VAR_pingone_client_id = $data.client_id
$env:TF_VAR_pingone_client_secret = $data.client_secret
$env:TF_VAR_pingone_environment_id = $data.environment_id

Write-Host "✓ Secrets loaded for $Environment"
```

### 4.3 Alternative: Windows Credential Manager

```powershell
# Store credentials
cmdkey /add:pingone-dev /user:svc-gitlab-runner /pass:your-secret

# Retrieve in pipeline
$cred = cmdkey /list:pingone-dev | Select-String "pingone-dev"
# Use $cred in Terraform runs
```

---

## 5. GITLAB CI/CD PIPELINE

### 5.1 `.gitlab-ci.yml` Configuration

```yaml
stages:
  - validate
  - plan
  - apply_dev
  - apply_qa
  - apply_uat
  - apply_prod

variables:
  TF_ROOT: "${CI_PROJECT_DIR}/terraform"
  TF_VERSION: "1.6.0"
  VAULT_ADDR: "http://vault.internal:8200"
  ARTIFACT_RETENTION_DAYS: 30

# Shared anchor for Windows runner
.windows_runner: &windows_runner
  tags:
    - windows
    - terraform
    - pingone
  shell: powershell

# ============================================================================
# STAGE 1: VALIDATE & FORMAT CHECK
# ============================================================================

tf_validate:
  <<: *windows_runner
  stage: validate
  script:
    - Write-Host "📋 Running Terraform Validate..."
    - cd $TF_ROOT
    - terraform init -backend=false
    - terraform validate
    - Write-Host "✓ Terraform config is valid"
  allow_failure: false
  artifacts:
    reports:
      terraform: [plan.json]
    expire_in: 30 days

tf_format:
  <<: *windows_runner
  stage: validate
  script:
    - Write-Host "🎨 Checking Terraform Format..."
    - cd $TF_ROOT
    - terraform fmt -check -recursive
    - Write-Host "✓ Terraform format is correct"
  allow_failure: true

tf_lint:
  <<: *windows_runner
  stage: validate
  script:
    - Write-Host "🔍 Running TFLint..."
    - cd $TF_ROOT
    - tflint --init
    - tflint --format compact
    - Write-Host "✓ TFLint checks passed"
  allow_failure: true

# ============================================================================
# STAGE 2: PLAN (Generate Terraform Plan for Review)
# ============================================================================

.plan_template: &plan_template
  <<: *windows_runner
  stage: plan
  script:
    - Write-Host "🔐 Fetching secrets from vault..."
    - .$CI_PROJECT_DIR/scripts/fetch-secrets.ps1 -Environment $ENVIRONMENT
    
    - Write-Host "📐 Initializing Terraform backend..."
    - cd $TF_ROOT
    - terraform init `
        -backend-config="key=pingone-$ENVIRONMENT.tfstate" `
        -backend-config="path=Z:\terraform-state\$ENVIRONMENT"
    
    - Write-Host "📋 Creating Terraform plan..."
    - terraform plan `
        -var-file="$CI_PROJECT_DIR/environments/$ENVIRONMENT.tfvars" `
        -out="$CI_PROJECT_DIR/tfplan-$ENVIRONMENT.tfplan"
    
    - Write-Host "✓ Plan created: tfplan-$ENVIRONMENT.tfplan"
  artifacts:
    paths:
      - "tfplan-*.tfplan"
    reports:
      terraform: [plan.json]
    expire_in: 7 days
  retry:
    max: 2
    when: runner_system_failure

plan_dev:
  <<: *plan_template
  variables:
    ENVIRONMENT: "dev"
  except:
    - tags

plan_qa:
  <<: *plan_template
  variables:
    ENVIRONMENT: "qa"
  only:
    - main

plan_uat:
  <<: *plan_template
  variables:
    ENVIRONMENT: "uat"
  only:
    - main

plan_prod:
  <<: *plan_template
  variables:
    ENVIRONMENT: "prod"
  only:
    - tags
    - main

# ============================================================================
# STAGE 3: APPLY DEV (Auto-apply on feature branches & main)
# ============================================================================

apply_dev:
  <<: *windows_runner
  stage: apply_dev
  script:
    - Write-Host "🚀 Deploying to DEV..."
    - Write-Host "🔐 Fetching secrets from vault..."
    - .$CI_PROJECT_DIR/scripts/fetch-secrets.ps1 -Environment "dev"
    
    - cd $TF_ROOT
    - terraform init `
        -backend-config="key=pingone-dev.tfstate" `
        -backend-config="path=Z:\terraform-state\dev"
    
    - Write-Host "✅ Applying Terraform configuration..."
    - terraform apply -auto-approve `
        -var-file="$CI_PROJECT_DIR/environments/dev.tfvars" `
        -lock=true -lock-timeout=5m
    
    - Write-Host "✓ DEV deployment complete"
  when: on_success
  retry:
    max: 1
  artifacts:
    paths:
      - "$TF_ROOT/.terraform"
    expire_in: 1 day

# ============================================================================
# STAGE 4: APPLY QA (Manual Approval Required)
# ============================================================================

apply_qa:
  <<: *windows_runner
  stage: apply_qa
  script:
    - Write-Host "🚀 Deploying to QA..."
    - Write-Host "🔐 Fetching secrets from vault..."
    - .$CI_PROJECT_DIR/scripts/fetch-secrets.ps1 -Environment "qa"
    
    - cd $TF_ROOT
    - terraform init `
        -backend-config="key=pingone-qa.tfstate" `
        -backend-config="path=Z:\terraform-state\qa"
    
    - terraform apply -auto-approve `
        -var-file="$CI_PROJECT_DIR/environments/qa.tfvars" `
        -lock=true -lock-timeout=5m
  when: manual
  only:
    - main
  retry:
    max: 1

# ============================================================================
# STAGE 5: APPLY UAT (Manual Approval Required)
# ============================================================================

apply_uat:
  <<: *windows_runner
  stage: apply_uat
  script:
    - Write-Host "🚀 Deploying to UAT..."
    - Write-Host "🔐 Fetching secrets from vault..."
    - .$CI_PROJECT_DIR/scripts/fetch-secrets.ps1 -Environment "uat"
    
    - cd $TF_ROOT
    - terraform init `
        -backend-config="key=pingone-uat.tfstate" `
        -backend-config="path=Z:\terraform-state\uat"
    
    - terraform apply -auto-approve `
        -var-file="$CI_PROJECT_DIR/environments/uat.tfvars" `
        -lock=true -lock-timeout=5m
  when: manual
  only:
    - main
  retry:
    max: 1

# ============================================================================
# STAGE 6: APPLY PROD (Manual Approval + Tag Required)
# ============================================================================

apply_prod:
  <<: *windows_runner
  stage: apply_prod
  script:
    - Write-Host "🚀 Deploying to PROD..."
    - Write-Host "🔐 Fetching secrets from vault..."
    - .$CI_PROJECT_DIR/scripts/fetch-secrets.ps1 -Environment "prod"
    
    - cd $TF_ROOT
    - terraform init `
        -backend-config="key=pingone-prod.tfstate" `
        -backend-config="path=Z:\terraform-state\prod"
    
    - Write-Host "📋 Running pre-production checks..."
    - .$CI_PROJECT_DIR/scripts/drift-detection.ps1 -Environment "prod"
    
    - Write-Host "✅ Applying Terraform configuration to PROD..."
    - terraform apply -auto-approve `
        -var-file="$CI_PROJECT_DIR/environments/prod.tfvars" `
        -lock=true -lock-timeout=10m
    
    - Write-Host "✓ PROD deployment complete - tag: $CI_COMMIT_TAG"
  when: manual
  only:
    - tags
    - main
  retry:
    max: 1
  environment:
    name: production
    action: deploy
```

---

## 6. TERRAFORM PROVIDER CONFIGURATION

### 6.1 `terraform/provider.tf`

```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    pingone = {
      source  = "pingidentity/pingone"
      version = "~> 0.18"
    }
  }

  cloud {
    organization = "your-org"
    hostname     = "app.terraform.io"
    
    workspaces {
      prefix = "pingone-"
    }
  }
}

# PingOne Provider
provider "pingone" {
  client_id      = var.pingone_client_id
  client_secret  = var.pingone_client_secret
  environment_id = var.pingone_environment_id
  region         = var.pingone_region
}

variable "pingone_client_id" {
  description = "PingOne Client ID (from vault)"
  type        = string
  sensitive   = true
}

variable "pingone_client_secret" {
  description = "PingOne Client Secret (from vault)"
  type        = string
  sensitive   = true
}

variable "pingone_environment_id" {
  description = "PingOne Environment ID"
  type        = string
  sensitive   = true
}

variable "pingone_region" {
  description = "PingOne Region (e.g., NorthAmerica, Europe)"
  type        = string
  default     = "NorthAmerica"
}
```

### 6.2 `terraform/backend.tf`

```hcl
# Windows file system backend (on-premises storage)
terraform {
  backend "local" {
    path = "terraform.tfstate"  # Overridden by -backend-config in CI/CD
  }
  
  # Alternative: Use remote backend (HTTP, S3, etc.)
  # backend "http" {
  #   address        = "http://state.internal/terraform"
  #   lock_address   = "http://state.internal/terraform/lock"
  #   unlock_address = "http://state.internal/terraform/lock"
  # }
}
```

---

## 7. ENVIRONMENT CONFIGURATION

### 7.1 `environments/dev.tfvars`

```hcl
environment_name = "development"
pingone_region   = "NorthAmerica"

# Authentication Policies
auth_policies = {
  mfa_required = true
  password_policy = {
    min_length      = 8
    require_numbers = true
    require_symbols = false
  }
}

# Application Configuration
applications = {
  "web-app-dev" = {
    name    = "Development Web Application"
    type    = "WEB_APP"
    sign_on = "OIDC"
  }
  "api-app-dev" = {
    name    = "Development API"
    type    = "SERVICE"
    sign_on = "CLIENT_CREDENTIALS"
  }
}

# User Configuration
users = {
  environment_admins = 5
  qa_testers         = 10
}

# MFA Settings
mfa_policies = {
  sms_enabled = true
  otp_enabled = true
  push_enabled = true
}

tags = {
  Environment = "dev"
  ManagedBy   = "Terraform"
  Owner       = "Platform-Team"
}
```

### 7.2 `environments/prod.tfvars`

```hcl
environment_name = "production"
pingone_region   = "NorthAmerica"

auth_policies = {
  mfa_required = true
  password_policy = {
    min_length      = 12
    require_numbers = true
    require_symbols = true
    expiration_days = 90
  }
  session_timeout = 3600  # 1 hour
}

applications = {
  "web-app-prod" = {
    name    = "Production Web Application"
    type    = "WEB_APP"
    sign_on = "OIDC"
  }
  "api-app-prod" = {
    name    = "Production API"
    type    = "SERVICE"
    sign_on = "CLIENT_CREDENTIALS"
  }
}

users = {
  environment_admins = 10
  operators          = 20
}

mfa_policies = {
  sms_enabled  = true
  otp_enabled  = true
  push_enabled = true
  duo_enabled  = true  # Additional security layer
}

tags = {
  Environment = "production"
  ManagedBy   = "Terraform"
  CriticalInfra = true
  Owner       = "Security-Team"
}
```

---

## 8. DRIFT DETECTION & MONITORING

### 8.1 `scripts/drift-detection.ps1`

```powershell
param(
    [string]$Environment = "prod"
)

Write-Host "🔍 Running drift detection for $Environment..."

$env:TF_VAR_pingone_client_id = $secret.client_id
$env:TF_VAR_pingone_client_secret = $secret.client_secret

cd "$PSScriptRoot/../terraform"

# Refresh state and check for drift
terraform refresh `
  -var-file="../environments/$Environment.tfvars"

$driftCheck = terraform plan `
  -var-file="../environments/$Environment.tfvars" `
  -detailed-exitcode

if ($driftCheck -eq 2) {
    Write-Host "⚠️  WARNING: Configuration drift detected!"
    Write-Host "Run 'terraform plan' to review changes."
    exit 1
} elseif ($driftCheck -eq 0) {
    Write-Host "✓ No drift detected - infrastructure matches config"
    exit 0
}
```

### 8.2 Scheduled Drift Detection Job

```yaml
drift_detection_scheduled:
  <<: *windows_runner
  stage: validate
  script:
    - .$CI_PROJECT_DIR/scripts/drift-detection.ps1 -Environment "prod"
  only:
    - schedules
  allow_failure: true
```

---

## 9. SIMULATION & DOCUMENTATION

### 9.1 Simulation Scenarios (`SIMULATION.md`)

```markdown
# Simulation & Testing Guide

## Scenario 1: New Authentication Policy
**Objective:** Add MFA requirement to all applications
**Steps:**
1. Create feature branch: `git checkout -b feature/add-mfa-requirement`
2. Modify `modules/authentication/main.tf`
3. Push changes and review plan in CI/CD pipeline
4. Merge to main (auto-applies to dev)
5. Request QA approval for qa environment
6. Validate in QA before UAT

## Scenario 2: User Onboarding Batch
**Objective:** Provision 50 new users with specific roles
**Steps:**
1. Update `environments/dev.tfvars` with user count
2. Use data source to assign roles
3. Generate plan showing 50 new user resources
4. Apply to dev environment

## Scenario 3: Rollback a Production Change
**Objective:** Revert recent configuration in prod
**Steps:**
1. Revert commit: `git revert <commit-hash>`
2. Create tag: `git tag -a v1.2.1-hotfix`
3. Pipeline detects tag and creates prod apply job
4. Manual approval triggers rollback apply
```

### 9.2 Architecture Documentation (`docs/architecture.md`)

```markdown
# PingOne IDP Infrastructure Architecture

## Component Diagram
```
GitLab Repository
    ↓
Windows GitLab Runner (on-premises)
    ↓
[Terraform] → [PingOne API]
    ↓
[Vault] (fetch secrets)
    ↓
[Terraform State] (Z:\terraform-state\)
    ↓
DEV → QA → UAT → PROD
```

## Data Flow
1. **Code Push:** Developer pushes Terraform code to GitLab
2. **Validation:** Format, lint, and validate checks run automatically
3. **Planning:** Terraform generates plan for each environment
4. **Approval:** Manual approval required for QA+
5. **Deployment:** Apply runs against PingOne API
6. **State:** State files stored in Windows shared directory

## Security Considerations
- API credentials stored in on-premises Vault (not GitLab)
- Terraform state locked during applies
- All operations logged in GitLab CI/CD
- Environment separation via tfvars files
- Manual approvals for QA and above
```

---

## 10. TROUBLESHOOTING & MAINTENANCE

### 10.1 Common Issues

| Issue | Cause | Resolution |
|-------|-------|-----------|
| "Terraform not found" | PATH not set | Add Terraform directory to system PATH |
| Vault auth fails | Invalid token or unreachable | Check VAULT_ADDR and vault service status |
| Plan timeout | Large state | Increase lock-timeout parameter |
| PowerShell execution policy | Default restricted | Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned` |
| State lock conflict | Previous run interrupted | Use `terraform force-unlock <lock-id>` |

### 10.2 Maintenance Tasks

**Weekly:**
- Review drift detection results
- Check Vault audit logs for API access

**Monthly:**
- Rotate PingOne API credentials in Vault
- Archive old terraform state files
- Review GitLab CI/CD job logs for failures

**Quarterly:**
- Update PingOne Terraform provider
- Review cost allocation per environment
- Audit IAM policies

---

## 11. GETTING STARTED CHECKLIST

- [ ] Windows GitLab Runner installed and registered
- [ ] HashiCorp Vault (or alternative) deployed on-premises
- [ ] PingOne credentials stored in Vault
- [ ] Windows shared directory (`Z:\terraform-state\`) created
- [ ] Terraform and TFLint installed on runner
- [ ] `.gitlab-ci.yml` committed to repo
- [ ] `fetch-secrets.ps1` configured with correct Vault address
- [ ] Test plan_dev job to validate pipeline
- [ ] Document team runbooks for approval process
- [ ] Set up scheduled drift detection job

---

## 12. ADDITIONAL REFERENCES

- [PingOne Terraform Provider Docs](https://registry.terraform.io/providers/pingidentity/pingone)
- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [HashiCorp Vault Setup Guide](https://www.vaultproject.io/docs/get-started)
- [Terraform Best Practices](https://www.terraform.io/cloud-docs/best-practices)

---

## 13. GAP RESOLUTIONS (from initial review)

The following gaps identified during plan review have been addressed in the scaffolded files:

| Gap | Resolution |
|---|---|
| **State locking** — local backend has no locking | `backend.tf` documents the limitation; jobs serialised by sequential stages + manual approvals; `resource_group` guidance added in `SETUP.md` |
| **Vault token injection** — `$env:VAULT_TOKEN` origin undefined | Switched to **AppRole auth** in `fetch-secrets.ps1`: Role ID (plain) + Secret ID (masked) stored as GitLab CI Variables; short-lived token fetched and revoked per job |
| **PingOne provider version** — `~> 0.18` outdated | Updated to `~> 1.0` in `terraform/provider.tf`; `region` renamed to `region_code` per v1 schema |
| **Missing qa/uat tfvars** | `environments/qa.tfvars` and `environments/uat.tfvars` created with environment-appropriate policy values |
| **No module resource examples** | All four modules (`authentication`, `users`, `applications`, `mfa`) contain actual `pingone_*` resources |
| **No destroy/rollback pipeline job** | `destroy_dev` and `destroy_qa` jobs added to `.gitlab-ci.yml` (manual, `main` only; PROD excluded) |
| **Branch strategy undocumented** | Documented in `README.md` — feature branches → dev auto; main → qa/uat/prod manual; tags → prod |
| **No failure notifications** | GitLab native pipeline failure emails cover this; Teams/Slack webhooks can be added via GitLab project integrations (no pipeline YAML change required) |
| **`.gitignore` not defined** | `.gitignore` created, excludes `*.tfstate`, `*.tfplan`, `.terraform/`, vault token files, PowerShell transcripts |
| **No `.tflint.hcl`** | `.tflint.hcl` created with `tflint-ruleset-terraform` plugin, naming convention, documentation, and required_version rules |