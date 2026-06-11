# Runbook — Day-2 Operations

## Approving a Deployment

1. Navigate to **GitLab → CI/CD → Pipelines**
2. Find the pipeline on `main` (or a tag)
3. Click into the pipeline graph
4. Click the **play** button on `apply_qa`, `apply_uat`, or `apply_prod`
5. Monitor the job log for `deployment complete`

> Only users with **Developer** role or above in GitLab can trigger manual jobs.

---

## Rotating PingOne API Credentials

1. In PingOne admin console, generate new client credentials for the Worker App
2. Update Vault:
   ```bash
   vault kv put secret/pingone/<env> \
     client_id="<new-client-id>" \
     client_secret="<new-client-secret>" \
     environment_id="<env-id>"
   ```
3. Trigger a `plan_<env>` job to verify the new credentials work
4. No Terraform state changes are needed (credentials are injected at runtime)

---

## State File Maintenance

### View current state
```powershell
Set-Location terraform\
terraform state list
```
Or in GitLab: **Operate → Terraform states → pingone-\<env\>**

### Remove a resource from state (without destroying it)
```powershell
# Use when a resource was deleted out-of-band and you want Terraform to forget it
terraform state rm 'module.applications.pingone_application.apps["web-app-dev"]'
```

### Import an existing PingOne resource into state
```powershell
# If a resource was created manually and you want Terraform to manage it
terraform import 'module.applications.pingone_application.apps["web-app-dev"]' <environment_id>/<application_id>
```

---

## Releasing to Production

Recommended flow:
1. Merge feature branch to `main`
2. Pipeline auto-applies to `dev`
3. Manually approve `apply_qa` → validate in QA
4. Manually approve `apply_uat` → sign-off from QA team
5. Create a version tag: `git tag -a v1.2.0 -m "Release 1.2.0" && git push origin v1.2.0`
6. Manually approve `apply_prod` on the tag pipeline

---

## Scheduled Drift Detection

- Runs daily via GitLab Schedule (see SETUP.md)
- If drift is detected, the job fails — GitLab sends a pipeline failure notification to configured recipients
- Review the plan output in the failed job log
- Either re-apply to restore state or update `.tfvars` to accept the change and re-plan

---

## Maintenance Checklist

### Weekly
- [ ] Review GitLab pipeline failures
- [ ] Check drift detection schedule results

### Monthly
- [ ] Rotate PingOne API credentials in Vault (all environments)
- [ ] Review Vault audit logs for secret access patterns
- [ ] Archive/clean old state backups from the file share

### Quarterly
- [ ] Update PingOne Terraform provider: bump version in `provider.tf`, run `terraform init -upgrade`
- [ ] Update TFLint ruleset plugin versions in `.tflint.hcl`
- [ ] Review GitLab Runner version and upgrade if needed
- [ ] Audit runner service account permissions on the state share
