# Architecture

## Component Diagram

```
Developer Workstation
        |
        | git push
        v
 GitLab Repository
        |
        | CI/CD webhook
        v
 Windows GitLab Runner (on-premises)
        |
   +---------+----------+
   |                    |
   v                    v
HashiCorp Vault    \\fileserver\terraform-state\
(AppRole auth)     (per-environment .tfstate files)
   |
   | TF_VAR_* env vars
   v
 Terraform CLI
        |
        | HTTPS API calls
        v
 PingOne API (cloud SaaS)
        |
        +-- Environment: dev
        +-- Environment: qa
        +-- Environment: uat
        +-- Environment: prod
```

## Data Flow

| Step | Description |
|---|---|
| 1. Push | Developer pushes Terraform code to GitLab |
| 2. Validate | Format check, `terraform validate`, TFLint, Checkov security scan |
| 3. Fetch secrets | `fetch-secrets.ps1` uses AppRole to get a short-lived Vault token, reads `secret/data/pingone/<env>`, exports `TF_VAR_*`, then revokes the token |
| 4. Plan | Terraform initialises against the UNC state path, generates a plan artefact |
| 5. Approve | QA, UAT, PROD require manual click-to-approve in GitLab UI |
| 6 | Apply | Terraform applies against the PingOne API; state written to GitLab Terraform state registry (`pingone-<env>`) with native locking |
| 7. Drift | Scheduled daily job compares live PingOne state vs Terraform config |

## Environment Isolation

Each environment has:
- A dedicated PingOne environment (separate `environment_id`)
- A dedicated Vault secret path (`secret/data/pingone/<env>`)
- A dedicated GitLab Terraform state (`pingone-<env>`) visible under **Operate → Terraform states**
- A dedicated `.tfvars` file with environment-specific policy values

## Security Boundaries

- API credentials are **never** stored in GitLab — only the Vault AppRole identifiers
- Vault tokens are short-lived (TTL: 5 min) and revoked after each secret fetch
- Terraform state files are stored in GitLab's state registry (HTTPS, access-controlled by GitLab project permissions and `CI_JOB_TOKEN`)
- `VAULT_SECRET_ID` is stored as a **masked** GitLab CI Variable (not visible in job logs)
- Plan artefacts (`.tfplan`) expire after 7 days in GitLab
