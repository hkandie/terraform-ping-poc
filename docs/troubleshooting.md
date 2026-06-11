# Troubleshooting

## Common Issues

### `terraform` or `tflint` not found

**Symptom:** `The term 'terraform' is not recognized`  
**Cause:** Binary not in `PATH` on the runner  
**Fix:**
```powershell
# Add to system PATH permanently
[Environment]::SetEnvironmentVariable(
  "PATH",
  "$([Environment]::GetEnvironmentVariable('PATH','Machine'));C:\tools\terraform;C:\tools\tflint",
  "Machine"
)
# Restart the gitlab-runner service
Restart-Service gitlab-runner
```

---

### PowerShell execution policy blocks scripts

**Symptom:** `File ... cannot be loaded because running scripts is disabled`  
**Fix:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

---

### Vault AppRole login fails

**Symptom:** `fetch-secrets.ps1` exits with `Vault AppRole login failed`  
**Causes and fixes:**

| Cause | Fix |
|---|---|
| `VAULT_ROLE_ID` or `VAULT_SECRET_ID` not set in GitLab | Add CI Variables in GitLab Settings → CI/CD → Variables |
| Vault unreachable from runner | Verify network connectivity: `Test-NetConnection -ComputerName vault.internal -Port 8200` |
| Secret ID expired or already used | Re-generate: `vault write -f auth/approle/role/gitlab-runner/secret-id` and update GitLab variable |
| AppRole role does not exist | See [docs/secrets-setup.md](secrets-setup.md) |

---

### `Error: expected "path" to be set` (backend config)

**Symptom:** Terraform init fails with backend config error  
**Cause:** `STATE_BASE_PATH` variable not expanded correctly in PowerShell pipeline  
**Fix:** Ensure the variable is defined in `.gitlab-ci.yml` under `variables:` and uses `\\\\` (double-escaped backslash for YAML):
```yaml
STATE_BASE_PATH: "\\\\fileserver\\terraform-state"
```

---

### State file locked from previous run

**Symptom:** `Error acquiring the state lock`  
**Cause:** The local backend does not support locking — this error should not occur with a local backend. If it does, a `.terraform.tfstate.lock.info` file may exist.  
**Fix:**
```powershell
# Remove stale lock file on the state share
Remove-Item "\\fileserver\terraform-state\<env>\.terraform.tfstate.lock.info" -Force
```

---

### PingOne API 401 Unauthorized

**Symptom:** `Error: API returned 401`  
**Causes and fixes:**

| Cause | Fix |
|---|---|
| Stale credentials in Vault | Rotate credentials — see Runbook |
| Wrong `environment_id` in Vault secret | Verify with `vault kv get secret/pingone/<env>` |
| Worker App missing required roles | Grant **Identity Data Admin** role in PingOne admin console |

---

### Plan shows unexpected `destroy` for existing resource

**Symptom:** Terraform plan wants to destroy a resource you didn't touch  
**Common causes:**
- `for_each` key changed (e.g., renamed an application key in `.tfvars`)  
- Provider version upgrade changed resource schema  

**Fix:**
```powershell
# Check what Terraform thinks is in state
terraform state show 'module.applications.pingone_application.apps["old-key"]'

# If the resource still exists under the old key, move it to the new key
terraform state mv \
  'module.applications.pingone_application.apps["old-key"]' \
  'module.applications.pingone_application.apps["new-key"]'
```

---

### TFLint `plugin not installed` on Windows

**Symptom:** `tflint --init` fails  
**Fix:** Ensure the runner has outbound HTTPS access to `github.com` for plugin download, or pre-install the plugin:
```powershell
# Pre-install tflint-ruleset-terraform to the runner
tflint --init --config="C:\path\to\.tflint.hcl"
```
