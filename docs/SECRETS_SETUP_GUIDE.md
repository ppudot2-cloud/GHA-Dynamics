# GitHub Secrets & Variables Setup Guide

This guide covers every secret and repository variable required by the Power Platform CI/CD workflows in this repository.

---

## 1. GitHub Secrets (Sensitive — never stored in plain text)

Navigate to: **Repository → Settings → Secrets and variables → Actions → Secrets**

| Secret Name | Description | Example |
|---|---|---|
| `PP_APP_ID` | Azure AD Application (Client) ID of the service principal | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `PP_CLIENT_SECRET` | Client secret for the service principal | `~AbCdEf1234567890...` |
| `PP_TENANT_ID` | Azure AD Tenant ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

> **Note:** All three secrets are required. The service principal must have the **Power Platform Administrator** or **System Administrator** role on every target environment.

---

## 2. GitHub Repository Variables (Non-sensitive configuration)

Navigate to: **Repository → Settings → Secrets and variables → Actions → Variables**

| Variable Name | Description | Example |
|---|---|---|
| `PP_SOLUTION_NAME` | Default solution unique name | `MyCoreSolution` |
| `PP_SDBX_URL` | Sandbox / developer source environment URL | `https://myorg-sdbx.crm.dynamics.com` |
| `PP_DEV_URL` | Dev environment URL | `https://myorg-dev.crm.dynamics.com` |
| `PP_INTG_URL` | Integration environment URL | `https://myorg-intg.crm.dynamics.com` |
| `PP_UAT_URL` | UAT environment URL | `https://myorg-uat.crm.dynamics.com` |
| `PP_PERF_URL` | Performance environment URL | `https://myorg-perf.crm.dynamics.com` |
| `PP_PROD_URL` | Production environment URL | `https://myorg-prod.crm.dynamics.com` |
| `PP_CHECKER_GEO` | Solution Checker geography | `UnitedStates` |
| `PP_DATA_SCHEMA_FILE` | Path to config migration data schema (optional) | `config/data-schema.xml` |

---

## 3. GitHub Environments (Approval Gates)

Navigate to: **Repository → Settings → Environments**

Create one environment for each deployment stage that requires human approval:

| Environment Name | Required Reviewers | Wait Timer | Used In |
|---|---|---|---|
| `Dev` | ✅ Yes — Dev Lead | — | `release-pipeline.yml`, `deploy-dev.yml` |
| `Intg` | ✅ Yes — Integration Lead | — | `release-pipeline.yml` |
| `UAT` | ✅ Yes — QA Lead | Optional | `release-pipeline.yml` |
| `Perf` | ✅ Yes — Performance Team | Optional | `release-pipeline.yml` |
| `Prod` | ✅ Yes — Release Manager | 5 min recommended | `release-pipeline.yml` |

For the `Rollback` workflow, the `rollback.yml` uses the target environment name, so `Prod` protection rules also apply to rollbacks.

---

## 4. Service Principal Setup (Azure AD)

### Step 1: Register an App in Azure AD
```
Azure Portal → Azure Active Directory → App Registrations → New Registration
  Name: Power Platform CI/CD Pipeline
  Supported account types: Single tenant
```

### Step 2: Create a Client Secret
```
App Registration → Certificates & secrets → New client secret
  Description: GitHub Actions
  Expiry: 24 months (set a calendar reminder to rotate)
```

Copy the **Value** immediately — it is only shown once. Store as `PP_CLIENT_SECRET`.

### Step 3: Register as Application User in Each Environment
For each environment (Sandbox, Dev, Intg, UAT, Perf, Prod):
```
Power Platform Admin Center → Environment → Settings → Users
  → Application Users → New App User
  → Add the App Registration above
  → Assign Security Role: System Administrator
```

Or use the `assign-user` action (see workflows/deploy-dev.yml for reference).

---

## 5. Deployment Settings Files

Each environment has a `deployment-settings.json` under `deployment-settings/{env}/`.

These files configure:
- **Connection References** — map logical names to actual connection IDs per environment
- **Environment Variables** — set environment-specific values without modifying the solution

### Token replacement
Values wrapped in `#{...}#` (e.g. `#{Prod_DataverseConnectionId}#`) are substituted at deploy time using GitHub repository variables or environment variables of the same name.

To add a new connection reference:
1. Find the `LogicalName` in your solution's `connectionreferences/` folder
2. Get the `ConnectionId` from Power Automate → Data → Connections → share URL
3. Add entries to each environment's `deployment-settings.json`

---

## 6. Branch Protection Rules

Navigate to: **Repository → Settings → Branches → Add rule for `main`**

Recommended settings:
- ✅ Require a pull request before merging
- ✅ Require status checks to pass (add: `🏗️ Build`, `🚀 Dev [Unmanaged]`)
- ✅ Require branches to be up to date before merging
- ✅ Require conversation resolution before merging
- ✅ Do not allow bypassing the above settings

---

## 7. Solution Folder Structure (Expected by Workflows)

```
src/
  solutions/
    MyCoreSolution/              ← matches PP_SOLUTION_NAME
      Other/
        Solution.xml             ← version number lives here
      Entities/
      WebResources/
      Workflows/
      ...

config/
  data-schema.xml                ← Configuration Migration Tool schema
  config-data.zip                ← exported config data (generated by export-solution.yml)

deployment-settings/
  dev/deployment-settings.json
  intg/deployment-settings.json
  uat/deployment-settings.json
  perf/deployment-settings.json
  prod/deployment-settings.json

.github/
  workflows/
    export-solution.yml
    _reusable-build.yml
    _reusable-deploy.yml
    release-pipeline.yml
    deploy-dev.yml
    rollback.yml
```

---

## 8. Quick Start Checklist

- [ ] App Registration created in Azure AD
- [ ] Client secret generated and stored as `PP_CLIENT_SECRET`
- [ ] App ID stored as `PP_APP_ID`
- [ ] Tenant ID stored as `PP_TENANT_ID`
- [ ] Application User added with System Administrator role in each environment
- [ ] Repository variables set for all `PP_*_URL` values
- [ ] `PP_SOLUTION_NAME` variable set
- [ ] GitHub Environments created: `Dev`, `Intg`, `UAT`, `Perf`, `Prod`
- [ ] Reviewers configured on `Dev`, `Intg`, `UAT`, `Perf`, `Prod` environments
- [ ] Branch protection rules enabled on `main`
- [ ] `deployment-settings.json` files populated with correct Connection IDs
- [ ] First export run via `export-solution.yml` to populate `src/solutions/`
