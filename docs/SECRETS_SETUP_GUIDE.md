# GitHub Secrets & Variables — Quick Reference

> This is a quick-reference card. For full setup instructions (Azure App Registration, OIDC, Key Vault, service principal) see [ENTERPRISE_DEVSECOPS_GUIDE.md](./ENTERPRISE_DEVSECOPS_GUIDE.md).

---

## GitHub Secret (1 required)

Navigate to: **GHA-Dynamics → Settings → Secrets and variables → Actions → Secrets**

| Secret | Description |
|---|---|
| `GHA_CORE_PAT` | Personal Access Token (or GitHub App token) with `repo` scope. Used to check out the private GHA-Core repository on runners and to create pull requests via `gh pr create`. Prefer a GitHub App over a PAT in production. |

> Power Platform credentials (`PP_APP_ID`, `PP_CLIENT_SECRET`, `PP_TENANT_ID`) are **not** stored as GitHub secrets. They are stored in Azure Key Vault and fetched at runtime via OIDC. See the enterprise guide for setup.

---

## GitHub Variables

Navigate to: **GHA-Dynamics → Settings → Secrets and variables → Actions → Variables**

### Azure / OIDC (required)

| Variable | Description |
|---|---|
| `AZURE_CLIENT_ID` | Client ID of the OIDC App Registration used for Azure login |
| `AZURE_TENANT_ID` | Your Azure AD Tenant ID (not the Contoso demo tenant) |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription containing the Key Vault |
| `AZURE_KEY_VAULT_NAME` | Name of the Key Vault that holds PP credentials |

### Power Platform environment URLs (required)

| Variable | Environment |
|---|---|
| `PP_SDBX_URL` | Sandbox (source of export) |
| `PP_DEV_URL` | Dev |
| `PP_INTG_URL` | Intg |
| `PP_UAT_URL` | UAT |
| `PP_FRS_URL` | FRS |
| `PP_PERF_URL` | Perf |
| `PP_PROD_URL` | Prod |

### JFrog (optional)

| Variable | Description |
|---|---|
| `JFROG_URL` | JFrog Artifactory base URL (e.g. `https://yourorg.jfrog.io/artifactory`) |
| `JFROG_REPO` | JFrog repository name (e.g. `powerplatform-solutions`) |

### Other (optional)

| Variable | Description |
|---|---|
| `PP_BASE_SOLUTIONS` | Comma-separated list of base solution names that must be installed before importing |
| `MULESOFT_ENABLED` | Set to `true` if solutions use Mulesoft connection references. Tells `reveille` to fetch Mulesoft credentials from AKV. |

---

## Azure Key Vault Secrets (fetched at runtime by `reveille`)

These are stored in Azure Key Vault, **not** in GitHub. Secret names must match exactly.

### Power Platform (always fetched)

| AKV Secret Name | Env Var | Description |
|---|---|---|
| `pp-app-id` | `PP_APP_ID` | Power Platform service principal Application (Client) ID |
| `pp-client-secret` | `PP_CLIENT_SECRET` | Power Platform service principal client secret |
| `pp-tenant-id` | `PP_TENANT_ID` | Azure AD Tenant ID |

### JFrog (fetched when `JFROG_URL` variable is set)

| AKV Secret Name | Env Var | Description |
|---|---|---|
| `jfrog-api-key` | `JFROG_TOKEN` | JFrog Artifactory API key |

### Mulesoft (fetched when `MULESOFT_ENABLED=true`)

| AKV Secret Name | Env Var | Description |
|---|---|---|
| `mulesoft-client-id` | `MULESOFT_CLIENT_ID` | Mulesoft connected app client ID |
| `mulesoft-client-secret` | `MULESOFT_CLIENT_SECRET` | Mulesoft connected app client secret |

### ServiceNow (fetched when `SERVICENOW_ENABLED=true` on an environment)

| AKV Secret Name | Env Var | Description |
|---|---|---|
| `snow-base-uri` | `SERVICENOWMURI` | ServiceNow instance base URL (e.g. `https://yourorg.service-now.com`) |
| `snow-oauth-client-id` | `SNOW_OAUTH_CLIENT_ID` | ServiceNow OAuth client ID |
| `snow-oauth-client-secret` | `SNOW_OAUTH_CLIENT_SECRET` | ServiceNow OAuth client secret |

Store these in the same Key Vault referenced by `AZURE_KEY_VAULT_NAME` on the environments where ServiceNow is active.

---

## GitHub Environments (approval gates + per-environment variables)

Navigate to: **GHA-Dynamics → Settings → Environments**

| Environment | Reviewers | Notes |
|---|---|---|
| `Dev` | Optional | Auto-deploys; first to receive every build |
| `Intg` | Recommended | Integration lead |
| `UAT` | Recommended | QA lead — UAT success triggers PR to main |
| `FRS` | Optional | Full regression suite team |
| `Perf` | Optional | Performance testing team |
| `Prod` | **Required** | Release manager — final gate before production |

Environment names are **case-sensitive** and must match exactly as shown above.

### Per-environment variables

Some variables are set at the **Environment** level rather than the repository level, so each environment can have a different value. Navigate to **Settings → Environments → [Environment name] → Environment variables**.

| Variable | Description | Example |
|---|---|---|
| `SERVICENOW_ENABLED` | Set to `true` to activate ServiceNow change management for this environment's deployments. When `true`, `reveille` fetches SNOW credentials from AKV and `deploy-all-solutions` opens/closes a CR around the import. | `true` |
| `AZURE_KEY_VAULT_NAME` | Override the default Key Vault for this environment. Useful when non-prod and prod use separate Key Vaults or separate service principals. | `kv-pp-prod` |
| `AZURE_CLIENT_ID` | Override the OIDC App Registration for this environment (if using per-environment app registrations). | — |

**Recommended `SERVICENOW_ENABLED` configuration:**

| Environment | Value |
|---|---|
| Dev | `false` (or unset) |
| Intg | `false` (or unset) |
| UAT | `true` |
| FRS | `true` |
| Perf | `true` |
| Prod | `true` |

---

## Branch Protection Rules for `main`

Navigate to: **GHA-Dynamics → Settings → Branches → Add rule for `main`**

Recommended settings:
- ✅ Require a pull request before merging
- ✅ Require status checks to pass
- ✅ Require branches to be up to date before merging
- ✅ Do not allow bypassing the above settings

> The merge of a `feature/*` PR to `main` is what triggers Pipeline 2 (`deploy-prod.yml`). Branch protection ensures this only happens after UAT is green and a human reviews the PR.
