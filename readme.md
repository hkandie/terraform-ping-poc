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

## Prerequisites

- Windows GitLab Runner registered with tags: `windows`, `terraform`, `pingone`
- HashiCorp Vault on-prem with AppRole auth and kv-v2 secrets at `secret/data/pingone/<env>`
- GitLab CI Variables set: `VAULT_ROLE_ID` (plain), `VAULT_SECRET_ID` (masked)
- Network share `\\fileserver\terraform-state\` with subdirs: `dev/`, `qa/`, `uat/`, `prod/`
- Runner service account has read/write access to the state share
- Terraform ≥ 1.5.0 and TFLint in system PATH on the runner

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
