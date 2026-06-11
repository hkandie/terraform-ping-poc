# Simulation & Testing Guide

Scenarios for demonstrating and validating the pipeline end-to-end.

---

## Scenario 1: Add MFA Requirement to All Applications

**Objective:** Enforce MFA sign-on across all environments.

```bash
git checkout -b feature/enforce-mfa
```

1. Open `environments/dev.tfvars` — confirm `mfa_required = true`
2. Open `terraform/modules/authentication/main.tf` — review the `pingone_sign_on_policy_action.mfa` resource
3. Push to GitLab:
   ```bash
   git add .
   git commit -m "feat: enforce MFA on sign-on policy"
   git push origin feature/enforce-mfa
   ```
4. **CI/CD pipeline triggers:** validate → plan → apply_dev (auto)
5. Review plan output in GitLab — look for `pingone_sign_on_policy_action` changes
6. Merge to `main` → manually approve `apply_qa`
7. Validate sign-on in QA environment via PingOne admin console

---

## Scenario 2: Tighten Password Policy for Production

**Objective:** Increase minimum password length and enable expiry in prod.

```bash
git checkout -b feature/prod-password-hardening
```

Edit `environments/prod.tfvars`:
```hcl
password_policy = {
  min_length      = 16   # was 12
  require_numbers = true
  require_symbols = true
  expiration_days = 60   # was 90
}
```

Push and observe:
- `plan_prod` job generates a plan showing `pingone_password_policy` will be **updated in-place** (no destroy/recreate)
- Manual approval required for `apply_prod`
- After apply, verify policy in PingOne admin console under Security → Password Policies

---

## Scenario 3: Add a New Application

**Objective:** Register a new OIDC web application in dev and qa.

Edit `environments/dev.tfvars` and `environments/qa.tfvars`:
```hcl
applications = {
  # ... existing apps ...
  "new-portal-dev" = {
    name    = "New Internal Portal (Dev)"
    type    = "WEB_APP"
    sign_on = "OIDC"
  }
}
```

Pipeline will show `1 resource to add` in the plan. After `apply_dev`, copy the output `application_ids` value from the GitLab job log and configure the redirect URI in PingOne admin console (redirect URIs must be set post-provisioning or managed via `oidc_options.redirect_uris` in the resource).

---

## Scenario 4: Rollback a Production Change

**Objective:** Revert a bad configuration change in prod.

```bash
# Identify the bad commit
git log --oneline -10

# Revert it
git revert <commit-hash> --no-edit
git push origin main
```

Pipeline stages run normally. Manually approve `apply_prod`.  
The reverted commit produces a plan that reverses the previous change.

For an emergency fix that cannot wait for UAT approval:

```bash
# On a machine with Vault access
export GITLAB_URL="https://gitlab.internal"
export GITLAB_PROJECT_ID="42"
export GITLAB_TOKEN="glpat-xxxxxxxxxxxx"

./scripts/apply-promotion.sh prod \
  http://vault.internal:8200 \
  $VAULT_ROLE_ID \
  $VAULT_SECRET_ID
```
```

The script prompts for explicit confirmation before applying.

---

## Scenario 5: Drift Detection Alert

**Objective:** Simulate and detect out-of-band infrastructure change.

1. Log into PingOne admin console and manually change the session timeout on the sign-on policy for prod
2. Wait for the scheduled drift detection pipeline (or manually trigger via GitLab Schedules)
3. The `drift_detection` job will output `DRIFT DETECTED` and exit 1 — creating a visible failure in the pipeline
4. Review the plan output in the job log to see exactly what drifted
5. Re-apply via `apply_prod` to restore desired state, or update `prod.tfvars` to accept the change

---

## Scenario 6: New Environment Onboarding

**Objective:** Add a `staging` environment between UAT and PROD.

1. Add `environments/staging.tfvars` (copy from `uat.tfvars`, adjust values)
2. Add `VAULT_SECRET_ID` equivalent for staging in Vault: `vault kv put secret/pingone/staging ...`
3. Add `plan_staging`, `apply_staging` jobs to `.gitlab-ci.yml` following the existing template pattern
4. Add `staging` as a `ValidateSet` option in all PowerShell scripts
5. Create the state directory: `\\fileserver\terraform-state\staging\`
