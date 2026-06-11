# Setup Guide

---

## 0. PingOne Prerequisites — Environments & Worker Apps

These steps are performed **once** by a PingOne Organisation Admin before any Terraform or pipeline work begins. The outputs (client ID, client secret, environment ID) are then stored in Vault for the pipeline to consume.

---

### 0.1 Sign In as Organisation Admin

1. Navigate to the PingOne admin console: `https://console.pingone.com` (NA) 
2. Sign in with an account that has the **Organisation Admin** role
3. Confirm you are in the correct organisation via the org switcher (top-left)

---

### 0.2 Create the Four Environments

Repeat the steps below for each of: **dev**, **qa**, **uat**, **prod**.

1. In the left sidebar, click **Environments**
2. Click **+ Add Environment**
3. Fill in the form:

   | Field | dev | qa | uat | prod |
   |---|---|---|---|---|
   | **Name** | `pingone-dev` | `pingone-qa` | `pingone-uat` | `pingone-prod` |
   | **Description** | Development environment | QA / test environment | User acceptance testing | Production |
   | **Type** | `Sandbox` | `Sandbox` | `Sandbox` | `Production` |
   | **Region** | North America (or your region) | same | same | same |
   | **Solution** | Customer Identity *(or your licensed solution)* | same | same | same |

4. Click **Save**
5. After creation, open the environment and note the **Environment ID** (shown in the URL: `…/environments/<environment-id>/…` or under **Settings → Environment**)

> Record the Environment ID — you will need it when storing credentials in Vault (step 0.4).

---

### 0.3 Create a Worker App in Each Environment

A **Worker App** uses the `CLIENT_CREDENTIALS` grant type to authenticate as a machine identity. Create one per environment so each can be rotated and scoped independently.

Repeat for each environment:

1. Switch to the target environment using the environment switcher (top-left)
2. Navigate to **Applications → Applications**
3. Click **+ Add Application**
4. Fill in the form:

   | Field | Value |
   |---|---|
   | **Application Name** | `terraform-worker-<env>` (e.g. `terraform-worker-dev`) |
   | **Description** | Terraform IaC pipeline worker — managed credentials, do not modify manually |
   | **Application Type** | **Worker** |

5. Click **Save**

#### Enable the Application

6. On the application page, toggle **Enabled** to ON (top-right of the app card)

#### Capture Credentials

7. Click the **Configuration** tab
8. Note the **Client ID** — this is `client_id` for Vault
9. Click **Generate New Secret** → copy the **Client Secret** immediately (it is only shown once) — this is `client_secret` for Vault

---

### 0.4 Assign Roles to Each Worker App

The Worker App needs sufficient permissions to manage PingOne resources via the API.

1. On the Worker App page, click the **Roles** tab
2. Click **Grant Roles**
3. Assign the following role **scoped to this environment**:

   | Role | Scope | Purpose |
   |---|---|---|
   | **Identity Data Admin** | This environment | Manage users, populations, applications, MFA policies, sign-on policies, password policies |

   > If you also need Terraform to manage the environment configuration itself (e.g. licences, branding), additionally assign **Environment Admin** scoped to this environment.

4. Click **Save**

> **Principle of least privilege:** Do not assign Organisation Admin to the Worker App. Scope all roles to the specific environment only.

---

### 0.5 Store Credentials in Vault

Once you have the credentials for all four environments, store them in Vault (see [docs/secrets-setup.md](docs/secrets-setup.md) for full Vault setup):

```bash
vault kv put secret/pingone/dev \
  client_id="<client-id-from-terraform-worker-dev>" \
  client_secret="<client-secret-from-terraform-worker-dev>" \
  environment_id="<environment-id-for-dev>"

vault kv put secret/pingone/qa \
  client_id="<client-id-from-terraform-worker-qa>" \
  client_secret="<client-secret-from-terraform-worker-qa>" \
  environment_id="<environment-id-for-qa>"

vault kv put secret/pingone/uat \
  client_id="<client-id-from-terraform-worker-uat>" \
  client_secret="<client-secret-from-terraform-worker-uat>" \
  environment_id="<environment-id-for-uat>"

vault kv put secret/pingone/prod \
  client_id="<client-id-from-terraform-worker-prod>" \
  client_secret="<client-secret-from-terraform-worker-prod>" \
  environment_id="<environment-id-for-prod>"
```

**Verify each secret was stored correctly:**

```bash
vault kv get secret/pingone/dev
vault kv get secret/pingone/qa
vault kv get secret/pingone/uat
vault kv get secret/pingone/prod
```

---

### 0.6 Validate Connectivity (Optional)

Before running the full pipeline, confirm each Worker App can authenticate against the PingOne API:

```bash
# Replace values for the environment you want to test
CLIENT_ID="<client-id>"
CLIENT_SECRET="<client-secret>"
ENV_ID="<environment-id>"
REGION="com"  # use "eu" for Europe, "asia" for Asia-Pacific

TOKEN_URL="https://auth.pingone.$REGION/$ENV_ID/as/token"

RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET")

ACCESS_TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [[ -n "$ACCESS_TOKEN" ]]; then
    echo "✓ Authentication successful for environment: $ENV_ID"
else
    echo "✗ Authentication failed — check client_id, client_secret, and environment_id"
    echo "Response: $RESPONSE"
fi
```

---

### 0.7 Checklist Before Running the Pipeline

- [ ] Four PingOne environments created (dev, qa, uat, prod) with Environment IDs noted
- [ ] Worker App `terraform-worker-<env>` created and **enabled** in each environment
- [ ] **Identity Data Admin** role assigned to each Worker App (scoped to its environment)
- [ ] Client ID and Client Secret captured for each Worker App
- [ ] All four secrets stored in Vault at `secret/pingone/<env>`
- [ ] Connectivity test passed for at least one environment
- [ ] Vault AppRole configured (see [docs/secrets-setup.md](docs/secrets-setup.md))
- [ ] GitLab CI Variables `VAULT_ROLE_ID` and `VAULT_SECRET_ID` set
- [ ] GitLab project has Terraform state enabled (default on; verify under **Operate → Terraform states**)

---

## 1. Linux GitLab Runner

### Prerequisites
- Linux distro: Ubuntu 20.04 LTS, Ubuntu 22.04 LTS, CentOS 7, or newer
- Bash shell
- Git, curl, jq installed
- Terraform ≥ 1.5.0 in PATH (`terraform` binary)
- TFLint in PATH (`tflint` binary)
- Checkov (optional): `pip install checkov` or system package
- Network access to: GitLab instance, Vault (`http://vault.internal:8200`), PingOne API

### Install and Register

```bash
# Create a directory for the runner
sudo mkdir -p /opt/gitlab-runner
cd /opt/gitlab-runner

# Download runner binary (choose appropriate URL for your architecture)
sudo curl -L \
  https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64 \
  -o gitlab-runner
sudo chmod +x gitlab-runner

# Create a symbolic link for easy access
sudo ln -sf /opt/gitlab-runner/gitlab-runner /usr/local/bin/gitlab-runner

# Register the runner (interactive — will prompt for token)
sudo gitlab-runner register \
  --url "https://your-gitlab-instance.com/" \
  --executor "shell" \
  --shell "bash" \
  --description "Linux IaC Runner — PingOne" \
  --tag-list "linux,terraform,pingone" \
  --run-untagged "false"

# Install and start the runner as a system service
sudo gitlab-runner install --user git
sudo systemctl start gitlab-runner
sudo systemctl enable gitlab-runner
sudo systemctl status gitlab-runner
```

### Verify Installation

```bash
gitlab-runner --version
terraform --version
tflint --version
```

---

## 2. Terraform State — GitLab-managed Backend

Terraform state is stored in **GitLab's built-in HTTP state backend**. No shared network drive or external object store is required.

### How it works

- Each environment gets its own named state: `pingone-dev`, `pingone-qa`, `pingone-uat`, `pingone-prod`
- GitLab issues a `CI_JOB_TOKEN` automatically for each pipeline job — Terraform uses this as the HTTP Basic Auth password
- The HTTP backend **natively supports state locking** (via `POST`/`DELETE` on the lock endpoint), preventing concurrent apply corruption
- State is visible in GitLab under **Operate → Terraform states**

### No manual setup required

GitLab creates the state on first `terraform init`. No directories or permissions need to be provisioned.

### Accessing state outside the pipeline

For manual operations (e.g., `./scripts/apply-promotion.sh`), use a **GitLab Personal Access Token** with `api` scope:

```bash
# Set once in your shell session — never hardcode
export GITLAB_URL="https://gitlab.internal"
export GITLAB_PROJECT_ID="42"   # numeric ID from GitLab project Settings → General
export GITLAB_TOKEN="glpat-xxxxxxxxxxxx"  # PAT with api scope
```

Then run `./scripts/apply-promotion.sh` — it reads these variables automatically.

### Viewing and managing state

In GitLab: **Operate → Terraform states** — lists all state files, their lock status, and serial number.

To delete a state (e.g., after `destroy_dev`):
```bash
curl --header "PRIVATE-TOKEN: <PAT>" \
  --request DELETE \
  "https://gitlab.internal/api/v4/projects/<project-id>/terraform/state/pingone-dev"
```

> **Note:** `resource_group: terraform-<env>` is still set on all apply jobs in `.gitlab-ci.yml`. This serialises any concurrent pipeline triggers for the same environment at the GitLab scheduler level, complementing the backend's own lock.

---

## 3. HashiCorp Vault — AppRole Setup

### Enable AppRole auth

```bash
vault auth enable approle
```

### Create a policy for PingOne secrets

```hcl
# pingone-reader.hcl
path "secret/data/pingone/*" {
  capabilities = ["read"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
```

```bash
vault policy write pingone-reader pingone-reader.hcl
```

### Create AppRole role

```bash
vault write auth/approle/role/gitlab-runner \
  token_policies="pingone-reader" \
  token_ttl=5m \
  token_max_ttl=10m \
  secret_id_ttl=0
```

### Retrieve Role ID and Secret ID

```bash
vault read auth/approle/role/gitlab-runner/role-id
vault write -f auth/approle/role/gitlab-runner/secret-id
```

### Store credentials in GitLab CI Variables

| Variable | Type | Value |
|---|---|---|
| `VAULT_ROLE_ID` | Variable (plain) | Role ID from above |
| `VAULT_SECRET_ID` | Variable (masked) | Secret ID from above |

---

## 4. PingOne Vault Secrets

Store per-environment credentials in Vault kv-v2:

```bash
vault kv put secret/pingone/dev \
  client_id="<worker-app-client-id>" \
  client_secret="<worker-app-client-secret>" \
  environment_id="<pingone-env-id>"

# Repeat for qa, uat, prod
vault kv put secret/pingone/qa  client_id="..." client_secret="..." environment_id="..."
vault kv put secret/pingone/uat client_id="..." client_secret="..." environment_id="..."
vault kv put secret/pingone/prod client_id="..." client_secret="..." environment_id="..."
```

The PingOne Worker App must have the **Identity Data Admin** role (or scoped equivalent) in the target PingOne environment.

---

## 5. Scheduled Drift Detection

In GitLab: **CI/CD → Schedules → New schedule**
- Description: `Daily drift detection`
- Interval: `0 6 * * *` (6 AM daily)
- Branch: `main`

The `drift_detection` job runs only when triggered by a schedule (`only: schedules`).
