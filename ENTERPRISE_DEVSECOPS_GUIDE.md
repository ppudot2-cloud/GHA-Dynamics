# Enterprise DevSecOps Setup Guide
## Power Platform CI/CD — GHA-Core + GHA-Dynamics Architecture

> **Audience:** DevSecOps engineers responsible for setting up and maintaining the pipeline.  
> **Scope:** Azure Key Vault integration, OIDC authentication, Power Platform service connection, and two-tier variable governance.

---

## Table of Contents

1. [Gap Analysis — Current vs Enterprise Standard](#1-gap-analysis)
2. [Architecture Overview — What You Are Building](#2-architecture-overview)
3. [Step-by-Step Azure Resource Setup](#3-azure-resource-setup)
4. [Power Platform Service Principal Setup](#4-power-platform-spn-setup)
5. [GitHub Repository Configuration](#5-github-repository-configuration)
6. [Variable Governance Architecture](#6-variable-governance-architecture)
7. [Azure Key Vault — Secret Inventory](#7-akv-secret-inventory)
8. [Verification Checklist](#8-verification-checklist)
9. [Ongoing Operations](#9-ongoing-operations)

---

## 1. Gap Analysis

The following table summarises what was assessed against enterprise DevSecOps standards, the severity of each finding, and the remediation status after this implementation.

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | `APP_ID`, `CLIENT_SECRET`, `TENANT_ID` stored as GitHub Secrets — plaintext at rest in GitHub's secrets store | 🔴 Critical | ✅ Fixed — moved to Azure Key Vault |
| 2 | GitHub Actions authenticated to Azure via client secret (`CLIENT_SECRET`) — rotatable but still a long-lived credential | 🔴 Critical | ✅ Fixed — OIDC / Workload Identity Federation (no secret) |
| 3 | Single SPN (`APP_ID`) used for ALL Power Platform environments — compromise of one credential exposes all environments | 🔴 Critical | ⚠️ Partially mitigated — AKV centralises the secret; environment-specific SPNs recommended as next step |
| 4 | No `permissions:` block on jobs — workflows ran with default over-permissive token scopes | 🟠 High | ✅ Fixed — `id-token: write, contents: read` added to all jobs |
| 5 | GitHub Actions pinned by tag (`@v4`) not SHA — tag can be silently moved by upstream maintainer | 🟠 High | ⚠️ Documented below — migrate to SHA pins as next step |
| 6 | No concurrency groups — concurrent deploys to the same environment possible, causing Dataverse async conflicts | 🟠 High | ⚠️ Documented below — add `concurrency:` to wrapper workflows |
| 7 | No SBOM generation — no software bill of materials for compliance audits | 🟡 Medium | ⚠️ Documented below — use `anchore/sbom-action` |
| 8 | No retry logic — transient Power Platform 429 / 503 errors cause permanent pipeline failures | 🟡 Medium | ⚠️ Documented below — add retry loop around import steps |
| 9 | `GHA_CORE_PAT` is a personal access token tied to an individual — token expires or user leaves | 🟡 Medium | ⚠️ Replace with GitHub App (see Section 9) |
| 10 | No variable governance — any project repo could shadow or omit required pipeline configuration | 🟡 Medium | ✅ Fixed — two-tier YAML + Merge-Variables.ps1 |
| 11 | No pipeline failure notifications — teams unaware of broken deploys until they manually check | 🟡 Medium | ⚠️ Documented below — add Slack/Teams webhook step |
| 12 | `JFrog_API_KEY` stored as GitHub Secret | 🟡 Medium | ✅ Fixed — moved to Azure Key Vault |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions Runner                                          │
│                                                                 │
│  1. Checkout caller repo (GHA-Dynamics)                        │
│  2. Checkout GHA-Core  ← uses GHA_CORE_PAT (only GH secret)   │
│  3. Azure OIDC Login   ← NO client secret — Federated Identity │
│  4. Fetch AKV Secrets  ← pp-app-id, pp-client-secret, etc.    │
│  5. Merge Variables    ← global-vars.yml + project-vars.yml    │
│  6. Pipeline work      ← uses ${{ env.PP_APP_ID }} etc.        │
└─────────────────────────────────────────────────────────────────┘

GitHub Secrets (1 only):        GitHub Variables (non-sensitive):
  GHA_CORE_PAT                    AZURE_CLIENT_ID
                                  AZURE_TENANT_ID
Azure Key Vault:                  AZURE_SUBSCRIPTION_ID
  pp-app-id                       AZURE_KEY_VAULT_NAME
  pp-client-secret
  pp-tenant-id
  jfrog-api-key

Variable files (source-controlled):
  GHA-Core/.github/config/global-vars.yml    ← protected global defaults
  GHA-Dynamics/.github/config/project-vars.yml ← project-specific values
```

**OIDC flow (no client secret for Azure auth):**
```
GitHub Actions → GitHub OIDC Provider → Issues JWT
JWT → Azure AD token endpoint → Validates Federated Identity Credential
Azure AD → Issues access token → Allows az keyvault secret show
```

---

## 3. Azure Resource Setup

### 3.1 Prerequisites

- Azure CLI installed and logged in: `az login`
- Owner or Contributor + User Access Administrator role on the subscription
- Power Platform admin access

### 3.2 Set Shell Variables

Run these in your terminal before executing any of the commands below. Replace ALL placeholder values.

```bash
# ── Your org identifiers ──────────────────────────────────────────
GITHUB_ORG="YOUR_GITHUB_ORG"              # e.g. contoso
GITHUB_REPO_DYNAMICS="GHA-Dynamics"       # project repo name
GITHUB_REPO_CORE="GHA-Core"              # core repo name

# ── Azure ────────────────────────────────────────────────────────
AZURE_SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AZURE_RESOURCE_GROUP="rg-powerplatform-cicd"
AZURE_LOCATION="eastus"                   # or your preferred region
AKV_NAME="akv-pp-cicd-prod"              # globally unique name (3-24 chars, alphanumeric+hyphens)
APP_REG_NAME="sp-powerplatform-cicd"     # App Registration display name

# ── Power Platform ───────────────────────────────────────────────
PP_TENANT_ID="yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
```

### 3.3 Create Resource Group

```bash
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --subscription "$AZURE_SUBSCRIPTION_ID"
```

### 3.4 Create Azure App Registration with Federated Identity

```bash
# ── Create App Registration ───────────────────────────────────────
APP_REG_JSON=$(az ad app create \
  --display-name "$APP_REG_NAME" \
  --sign-in-audience "AzureADMyOrg" \
  --query "{appId:appId, objectId:id}" \
  --output json)

AZURE_CLIENT_ID=$(echo "$APP_REG_JSON" | jq -r '.appId')
APP_OBJECT_ID=$(echo "$APP_REG_JSON"  | jq -r '.objectId')

echo "App Registration created:"
echo "  Client ID   : $AZURE_CLIENT_ID"
echo "  Object ID   : $APP_OBJECT_ID"

# ── Create Service Principal ──────────────────────────────────────
az ad sp create --id "$AZURE_CLIENT_ID"
SP_OBJECT_ID=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv)
```

### 3.5 Add Federated Identity Credentials

Federated credentials allow GitHub Actions to authenticate with Azure AD using a short-lived OIDC token — **no client secret required**.

Add credentials for each scope you need. The `subject` claim determines which workflows can authenticate.

```bash
# ── Credential 1: main branch (build, deploy-dev, release pipeline) ──
az ad app federated-credential create \
  --id "$APP_OBJECT_ID" \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO_DYNAMICS"':ref:refs/heads/main",
    "description": "GitHub Actions from main branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# ── Credential 2: Production environment (Prod deploy gate) ──────────
az ad app federated-credential create \
  --id "$APP_OBJECT_ID" \
  --parameters '{
    "name": "github-actions-env-prod",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO_DYNAMICS"':environment:Production",
    "description": "GitHub Actions from Production environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# ── Credential 3: Pull requests ───────────────────────────────────────
az ad app federated-credential create \
  --id "$APP_OBJECT_ID" \
  --parameters '{
    "name": "github-actions-pr",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO_DYNAMICS"':pull_request",
    "description": "GitHub Actions from pull requests",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# ── Credential 4: workflow_dispatch (rollback, manual triggers) ───────
az ad app federated-credential create \
  --id "$APP_OBJECT_ID" \
  --parameters '{
    "name": "github-actions-workflow-dispatch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO_DYNAMICS"':ref:refs/heads/main",
    "description": "GitHub Actions workflow_dispatch from main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

> **Note:** The `subject` must exactly match what GitHub sends in the OIDC token. For `workflow_dispatch` on `main`, the subject is `repo:ORG/REPO:ref:refs/heads/main`. For environment-gated jobs, it is `repo:ORG/REPO:environment:EnvName`.

### 3.6 Create Azure Key Vault

```bash
# ── Create Key Vault ──────────────────────────────────────────────
az keyvault create \
  --name "$AKV_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --sku standard \
  --enable-rbac-authorization true \
  --retention-days 90

# ── Capture the Key Vault resource ID ────────────────────────────
AKV_ID=$(az keyvault show --name "$AKV_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id -o tsv)

echo "Key Vault created: $AKV_ID"
```

> **Why `--enable-rbac-authorization true`?** RBAC-mode Key Vault uses Azure RBAC roles instead of legacy access policies. This integrates cleanly with Workload Identity and makes auditing simpler.

### 3.7 Assign Key Vault Roles

```bash
# ── Grant the App Registration 'Key Vault Secrets User' ──────────
# This allows it to READ secrets (not create/delete them).
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$AKV_ID"

# ── Grant YOUR user 'Key Vault Secrets Officer' for initial setup ─
MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee-object-id "$MY_OBJECT_ID" \
  --assignee-principal-type User \
  --scope "$AKV_ID"

echo "Role assignments complete."
```

---

## 4. Power Platform SPN Setup

The Power Platform uses a separate Azure AD App Registration (or the same one — your choice) registered as an application user in each Dataverse environment. The **client secret** for this SPN is what lives in Azure Key Vault.

### 4.1 Option A — Use the Same App Registration (Simpler)

You can re-use `sp-powerplatform-cicd` for both Azure AKV access (via OIDC) and Power Platform authentication (via client secret). This means:
- OIDC Federated Credential → authenticates to Azure, reads from AKV
- Client Secret → stored IN AKV, used for PAC CLI authentication to Dataverse

```bash
# ── Create a client secret FOR POWER PLATFORM AUTH ONLY ──────────
# This secret is stored in AKV — it never touches GitHub.
PP_SECRET_JSON=$(az ad app credential reset \
  --id "$AZURE_CLIENT_ID" \
  --display-name "pp-cicd-secret" \
  --years 2 \
  --query "{password:password}" \
  --output json)

PP_CLIENT_SECRET=$(echo "$PP_SECRET_JSON" | jq -r '.password')
echo "PP client secret created (store this — shown once only)"
```

> **Option B — Separate App Registration for PP:** Create a second App Registration specifically for Power Platform. Its client secret goes into AKV. The first App Registration (with Federated Credentials) reads that secret from AKV at runtime. This gives better separation of concerns but adds complexity. Recommended for large enterprises.

### 4.2 Register the SPN as an Application User in Each PP Environment

This must be done in the Power Platform Admin Center for **every** Dataverse environment (Dev, Intg, UAT, Perf, Prod).

**Option A — Power Platform Admin Center (UI):**
1. Go to [admin.powerplatform.microsoft.com](https://admin.powerplatform.microsoft.com)
2. Select your environment → **Settings → Users + permissions → Application users**
3. Click **New app user** → Select the App Registration (`sp-powerplatform-cicd`)
4. Assign the **System Administrator** security role (required for solution import/export)
5. Repeat for all environments

**Option B — PAC CLI (scriptable):**
```bash
# Requires PAC CLI installed and authenticated as an admin
pac admin assign-user \
  --environment "https://YOUR-ORG-dev.crm.dynamics.com" \
  --application-id "$AZURE_CLIENT_ID" \
  --role "System Administrator"
```

### 4.3 Store Power Platform Credentials in Azure Key Vault

```bash
# ── Store PP credentials ──────────────────────────────────────────
az keyvault secret set \
  --vault-name "$AKV_NAME" \
  --name "pp-app-id" \
  --value "$AZURE_CLIENT_ID"

az keyvault secret set \
  --vault-name "$AKV_NAME" \
  --name "pp-client-secret" \
  --value "$PP_CLIENT_SECRET"

az keyvault secret set \
  --vault-name "$AKV_NAME" \
  --name "pp-tenant-id" \
  --value "$PP_TENANT_ID"

echo "✅ Power Platform credentials stored in AKV."
```

### 4.4 Store JFrog API Key in Azure Key Vault

```bash
# ── Replace <YOUR_JFROG_API_KEY> with your actual API key ─────────
az keyvault secret set \
  --vault-name "$AKV_NAME" \
  --name "jfrog-api-key" \
  --value "<YOUR_JFROG_API_KEY>"
```

---

## 5. GitHub Repository Configuration

### 5.1 GitHub Secrets (Settings → Secrets and variables → Actions → Secrets)

Only **one** secret needs to be stored in GitHub now:

| Secret Name | Value | Where Used |
|-------------|-------|------------|
| `GHA_CORE_PAT` | A GitHub Personal Access Token (classic) with `repo` scope on `GHA-Core` | Checkout of GHA-Core before OIDC login is possible |

> **Better alternative to PAT:** Create a [GitHub App](https://docs.github.com/en/apps/creating-github-apps) with `Contents: Read` permission on GHA-Core, install it on the organisation, and use the App's private key + installation token instead. This does not expire and is not tied to an individual. See Section 9 for instructions.

### 5.2 GitHub Variables (Settings → Secrets and variables → Actions → Variables)

These are **non-sensitive resource identifiers** — safe to store as variables, not secrets.

Set these on the **GHA-Dynamics** repository:

| Variable Name | Value | Notes |
|---------------|-------|-------|
| `AZURE_CLIENT_ID` | `<App Registration client ID>` | Output from Section 3.4 |
| `AZURE_TENANT_ID` | `<Azure AD tenant ID>` | Your AAD tenant |
| `AZURE_SUBSCRIPTION_ID` | `<Azure subscription ID>` | Your subscription |
| `AZURE_KEY_VAULT_NAME` | `akv-pp-cicd-prod` | The AKV name from Section 3.6 |

Also set the Power Platform environment URLs (these are referenced by the thin wrapper workflows):

| Variable Name | Example Value |
|---------------|---------------|
| `PP_DEV_URL` | `https://YOUR-ORG-dev.crm.dynamics.com` |
| `PP_INTG_URL` | `https://YOUR-ORG-intg.crm.dynamics.com` |
| `PP_UAT_URL` | `https://YOUR-ORG-uat.crm.dynamics.com` |
| `PP_PERF_URL` | `https://YOUR-ORG-perf.crm.dynamics.com` |
| `PP_PROD_URL` | `https://YOUR-ORG-prod.crm.dynamics.com` |
| `PP_SDBX_URL` | `https://YOUR-ORG-sdbx.crm.dynamics.com` |
| `JFROG_URL` | `https://YOUR-COMPANY.jfrog.io/artifactory` |

### 5.3 Replace YOUR_ORG in Workflow Files

Update the GHA-Core checkout step in all reusable workflows:

```bash
# In GHA-Core/.github/workflows/_reusable-build.yml,
# _reusable-deploy.yml, _reusable-rollback.yml, _reusable-deploy-dev.yml:
# Replace:  repository: YOUR_ORG/GHA-Core
# With:     repository: contoso/GHA-Core   (your actual org)
```

---

## 6. Variable Governance Architecture

### 6.1 File Locations and Purpose

```
GHA-Core/
└── .github/
    ├── config/
    │   └── global-vars.yml        ← Global defaults + protected keys list
    └── scripts/
        └── Merge-Variables.ps1    ← Enforcement script

GHA-Dynamics/
└── .github/
    └── config/
        └── project-vars.yml       ← Project-specific values (cannot override protected keys)
```

### 6.2 How It Works at Pipeline Time

```
Pipeline start
     │
     ▼
1b. Checkout GHA-Core (.ci/)
     │
     ▼
1e. Run Merge-Variables.ps1
     │
     ├── Read .ci/.github/config/global-vars.yml
     │     → Load protected_keys list
     │     → Load global variable defaults
     │
     ├── Read .github/config/project-vars.yml
     │     → Load project-specific variables
     │
     ├── GOVERNANCE CHECK
     │     → Any project key in protected_keys? → EXIT 1 (pipeline stops)
     │
     └── MERGE + EXPORT to $GITHUB_ENV
           → All subsequent steps use ${{ env.VAR_NAME }}
```

### 6.3 Protected Keys

The following keys in `global-vars.yml` **cannot** be overridden by any project:

| Key | Reason |
|-----|--------|
| `PP_CHECKER_GEO` | Solution Checker must use the same geographic endpoint org-wide |
| `PP_CHECKER_ERROR_LEVEL` | Security gate threshold — projects cannot lower the bar |
| `JFROG_REPO` | All projects publish to the same Artifactory repository |
| `DEFAULT_SOLUTION_TYPE` | All solutions must be managed in upper environments |
| `ENABLE_BACKUP` | Backups before deploy are mandatory — cannot be disabled |
| `ENABLE_BLOCKING_CHECK` | Async operation check is mandatory |
| `AZURE_TENANT_ID` | Single AAD tenant — prevents identity confusion |
| `AZURE_CLIENT_ID` | Single SPN — projects cannot substitute their own |
| `AZURE_SUBSCRIPTION_ID` | Single subscription — prevents cost leakage |
| `AZURE_KEY_VAULT_NAME` | Centralised secret store — cannot point elsewhere |
| `GHA_CORE_ORG` | Prevents projects pointing at forked core repos |
| `GHA_CORE_REPO` | Same as above |

### 6.4 Adding a New Protected Key

1. Add the key name to `protected_keys:` in `GHA-Core/.github/config/global-vars.yml`
2. Add the key with its default value to `variables:` in the same file
3. Raise a PR to GHA-Core — any project with that key in their `project-vars.yml` will fail at the next pipeline run with a clear error

### 6.5 Project Variable Conventions

In `GHA-Dynamics/.github/config/project-vars.yml`:
- Add environment URLs (`PP_DEV_URL`, `PP_PROD_URL`, etc.)
- Add project-specific configuration (`PP_SOLUTION_NAME`, `PP_DATA_SCHEMA_FILE`)
- Do **not** add keys from the protected list — the pipeline will reject them

---

## 7. AKV Secret Inventory

Complete list of secrets that must exist in Azure Key Vault before the first pipeline run:

| AKV Secret Name | Maps to `$env:` | Description | Rotation Trigger |
|-----------------|-----------------|-------------|------------------|
| `pp-app-id` | `PP_APP_ID` | Power Platform App Registration client ID | App Registration change |
| `pp-client-secret` | `PP_CLIENT_SECRET` | Power Platform client secret | Every 1–2 years (or on compromise) |
| `pp-tenant-id` | `PP_TENANT_ID` | Azure AD tenant ID for Power Platform | Tenant migration only |
| `jfrog-api-key` | `JFROG_API_KEY` | JFrog Artifactory API key | Every 90 days (recommended) |

**Verify all secrets are present:**
```bash
az keyvault secret list --vault-name "$AKV_NAME" \
  --query "[].name" -o table
```

**Expected output:**
```
Name
------------------
jfrog-api-key
pp-app-id
pp-client-secret
pp-tenant-id
```

---

## 8. Verification Checklist

Run through this checklist after completing setup, in order:

### 8.1 Azure Resources

```bash
# ✅ App Registration exists
az ad app show --id "$AZURE_CLIENT_ID" --query displayName -o tsv

# ✅ Federated credentials created (should show 4 entries)
az ad app federated-credential list --id "$APP_OBJECT_ID" --query "[].name" -o table

# ✅ Key Vault exists and is RBAC-enabled
az keyvault show --name "$AKV_NAME" --query "properties.enableRbacAuthorization" -o tsv
# Expected: true

# ✅ Service Principal has Key Vault Secrets User role
az role assignment list \
  --assignee "$SP_OBJECT_ID" \
  --scope "$AKV_ID" \
  --query "[].roleDefinitionName" -o table
# Expected: Key Vault Secrets User

# ✅ All 4 secrets exist in AKV
az keyvault secret list --vault-name "$AKV_NAME" --query "length(@)" -o tsv
# Expected: 4
```

### 8.2 Power Platform

```bash
# ✅ App user exists in each environment — check via Admin Center UI or:
pac auth create --url "https://YOUR-ORG-dev.crm.dynamics.com" \
  --appId "$AZURE_CLIENT_ID" \
  --clientSecret "$PP_CLIENT_SECRET" \
  --tenant "$PP_TENANT_ID"
pac org who
# Expected: shows org details, not an error
```

### 8.3 GitHub Configuration

| Item | Where to Check | Expected |
|------|----------------|----------|
| `GHA_CORE_PAT` secret | Settings → Secrets → Actions | Present |
| `AZURE_CLIENT_ID` variable | Settings → Variables → Actions | Non-empty GUID |
| `AZURE_TENANT_ID` variable | Settings → Variables → Actions | Non-empty GUID |
| `AZURE_SUBSCRIPTION_ID` variable | Settings → Variables → Actions | Non-empty GUID |
| `AZURE_KEY_VAULT_NAME` variable | Settings → Variables → Actions | `akv-pp-cicd-prod` |
| `PP_DEV_URL` variable | Settings → Variables → Actions | Dynamics URL |

### 8.4 First Pipeline Run

1. Trigger the pipeline with `mock_deploy: true` first — this skips the OIDC login and AKV fetch, confirming the GHA_CORE_PAT and checkout work
2. Trigger with `mock_deploy: false` on a non-production branch — this exercises the full OIDC → AKV → PP flow
3. Check the "Fetch secrets from Azure Key Vault" step output — all values should be masked (`***`) in the logs

---

## 9. Ongoing Operations

### 9.1 Rotating the Power Platform Client Secret

```bash
# 1. Create a new secret in AKV (update in place — no downtime)
NEW_PP_SECRET=$(az ad app credential reset \
  --id "$AZURE_CLIENT_ID" \
  --display-name "pp-cicd-secret-$(date +%Y%m)" \
  --years 2 \
  --query "password" -o tsv)

# 2. Update AKV secret (new version is created; old version kept for rollback)
az keyvault secret set \
  --vault-name "$AKV_NAME" \
  --name "pp-client-secret" \
  --value "$NEW_PP_SECRET"

# 3. Test the pipeline — no code change needed (AKV always serves latest version)
# 4. After pipeline passes, delete the old App Registration credential
az ad app credential list --id "$AZURE_CLIENT_ID" --query "[].keyId" -o table
az ad app credential delete --id "$AZURE_CLIENT_ID" --key-id "<old-key-id>"
```

### 9.2 Replacing GHA_CORE_PAT with a GitHub App (Recommended)

PATs are tied to an individual and expire. GitHub Apps are better:

```bash
# 1. Create a GitHub App at: github.com/organizations/YOUR_ORG/settings/apps/new
#    - Name: "GHA-Core CI Access"
#    - Permissions: Repository > Contents: Read-only
#    - Install on: GHA-Core only

# 2. Download the private key (.pem) from the App settings page

# 3. Store the private key and App ID in AKV:
az keyvault secret set \
  --vault-name "$AKV_NAME" \
  --name "gha-app-id" \
  --value "<your-github-app-id>"

az keyvault secret set \
  --vault-name "$AKV_NAME" \
  --name "gha-app-private-key" \
  --value "$(cat your-app.pem)"

# 4. In the workflow, use actions/create-github-app-token before checkout:
#    - uses: actions/create-github-app-token@v2
#      with:
#        app-id: ${{ env.GHA_APP_ID }}
#        private-key: ${{ env.GHA_APP_PRIVATE_KEY }}
#        repositories: GHA-Core
```

### 9.3 Pin GitHub Actions to SHA (Security Hardening)

Tag-pinned actions (`@v4`) can be silently moved. Pin by commit SHA:

```bash
# Find the current SHA for a tag:
gh api repos/actions/checkout/git/refs/tags/v4 --jq '.object.sha'

# Then in your workflow replace:
#   uses: actions/checkout@v4
# With:
#   uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

# Tool to automate this: https://github.com/mheap/pin-github-action
```

### 9.4 Add Concurrency Groups (Prevent Parallel Deploys)

Add to each environment deploy job in `release-pipeline.yml` (GHA-Dynamics):

```yaml
concurrency:
  group: deploy-${{ inputs.environment_name }}-${{ github.ref }}
  cancel-in-progress: false  # queue rather than cancel
```

### 9.5 Add Failure Notifications

Add at the end of `release-pipeline.yml` as a `notify-failure` job:

```yaml
  notify-failure:
    name: "Notify on failure"
    runs-on: ubuntu-latest
    needs: [build, deploy-dev, deploy-intg, deploy-uat, deploy-prod]
    if: failure()
    steps:
      - name: Send Teams notification
        uses: skitionek/notify-microsoft-teams@master
        with:
          webhook_url: ${{ vars.TEAMS_WEBHOOK_URL }}
          job: ${{ toJson(job) }}
          steps: ${{ toJson(steps) }}
```

### 9.6 Environment-Specific SPNs (Future Hardening)

Currently one SPN accesses all environments. To limit blast radius:

1. Create one App Registration per environment (e.g., `sp-pp-dev`, `sp-pp-prod`)
2. Store each SPN's credentials in AKV under environment-prefixed names:
   - `pp-dev-app-id`, `pp-dev-client-secret`
   - `pp-prod-app-id`, `pp-prod-client-secret`
3. Update the AKV fetch step in `_reusable-deploy.yml` to use `inputs.environment_name` to select the correct secrets
4. Grant each SPN only to its own Dataverse environment
5. Use GitHub Environments with stricter reviewer gates for prod-scoped secrets

---

## Summary — What Was Changed

| File | Change |
|------|--------|
| `GHA-Core/.github/workflows/_reusable-build.yml` | Added OIDC login + AKV fetch + variable merge steps; replaced all `secrets.*` refs with `env.*`; added `permissions: id-token: write` |
| `GHA-Core/.github/workflows/_reusable-deploy.yml` | Same as build |
| `GHA-Core/.github/workflows/_reusable-rollback.yml` | Same as build |
| `GHA-Core/.github/config/global-vars.yml` | **New** — global defaults + protected_keys |
| `GHA-Dynamics/.github/config/project-vars.yml` | **New** — project-specific variables |
| `GHA-Core/.github/scripts/Merge-Variables.ps1` | **New** — governance enforcement script |

