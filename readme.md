# PingOne IDP Terraform — GitLab IaC Pipeline

Manages PingOne Identity Provider resources via Terraform, deployed through a Windows GitLab Runner with secrets sourced from an on-premises HashiCorp Vault.

## Quick Links

| Document | Purpose |
|---|---|
| [SETUP.md](SETUP.md) | Runner installation, Vault setup, state share |
| [SIMULATION.md](SIMULATION.md) | Testing scenarios and demo walkthroughs |
| [docs/architecture.md](docs/architecture.md) | Component diagram and data flow |
| [docs/runbook.md](docs/runbook.md) | Day-2 operations and approvals |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failure resolution |
| [docs/secrets-setup.md](docs/secrets-setup.md) | Vault AppRole configuration |

## Pipeline Stages

```
validate → plan → apply_dev → apply_qa (manual) → apply_uat (manual) → apply_prod (manual)
```

| Stage | Trigger | Approval |
|---|---|---|
| validate | All pushes | Automatic |
| plan | All pushes | Automatic |
| apply_dev | Merge to `main` | Automatic |
| apply_qa | Merge to `main` | Automatic |
| apply_uat | `main` only | Manual |
| apply_prod | `main` + tags | Manual |

## Branch Strategy

| Branch Pattern | Deploys To |
|---|---|
| `feature/*`, any branch | dev (auto) |
| `main` | dev (auto) → qa/uat/prod (manual) |
| `v*` tags | prod (manual, in addition to main) |

## Installing Terraform on Linux

1. Visit [https://developer.hashicorp.com/terraform/install#linux](https://developer.hashicorp.com/terraform/install#linux) and download the appropriate Linux binary for your architecture (usually `amd64`), version ≥ 1.5.0.
2. Extract the zip — it contains a single `terraform` binary.
3. Move the binary to a standard location:
   ```bash
   sudo mv terraform /usr/local/bin/
   sudo chmod +x /usr/local/bin/terraform
   ```
   Or add it to your user PATH in `~/.bashrc` or `~/.zshrc`:
   ```bash
   export PATH="$HOME/tools/terraform:$PATH"
   ```
4. Verify installation:
   ```bash
   terraform -version
   ```
   Expected output: `Terraform v1.x.x`

> For the GitLab Runner service account, ensure the PATH is configured at the system level or through the runner's startup script so it inherits the binary location.

## Prerequisites

- Linux GitLab Runner registered with tags: `linux`, `terraform`, `pingone`
- HashiCorp Vault on-prem with AppRole auth and kv-v2 secrets at `secret/data/pingone/<env>`
- GitLab CI Variables set: `VAULT_ROLE_ID` (plain), `VAULT_SECRET_ID` (masked)
- Terraform ≥ 1.5.0, TFLint, curl, and jq installed on the Linux runner
- All scripts in `scripts/` directory have execute permissions: `chmod +x scripts/*.sh`

## Repository Structure

```
.
├── .gitlab-ci.yml              # CI/CD pipeline
├── .gitignore
├── .tflint.hcl                 # TFLint ruleset config
├── terraform/
│   ├── provider.tf
│   ├── backend.tf
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── authentication/    # Sign-on policies, password policies
│       ├── users/             # Populations
│       ├── applications/      # OIDC / service apps
│       └── mfa/               # MFA device policy
├── environments/
│   ├── dev.tfvars
│   ├── qa.tfvars
│   ├── uat.tfvars
│   └── prod.tfvars
├── scripts/
│   ├── fetch-secrets.ps1      # Vault AppRole secret retrieval
│   ├── validate.ps1           # Local pre-push validation
│   ├── apply-promotion.ps1    # Manual promotion outside CI
│   └── drift-detection.ps1   # Config drift check
└── docs/
    ├── architecture.md
    ├── runbook.md
    ├── troubleshooting.md
    └── secrets-setup.md
```
