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

---

## Azure Key Vault Secrets (fetched at runtime by ci-bootstrap)

These are stored in Azure Key Vault, **not** in GitHub. Secret names must match exactly.

| AKV Secret Name | Description |
|---|---|
| `pp-app-id` | Power Platform service principal Application (Client) ID |
| `pp-client-secret` | Power Platform service principal client secret |
| `pp-tenant-id` | Azure AD Tenant ID |
| `jfrog-api-key` | JFrog Artifactory API key (only needed if JFROG_URL is set) |

---

## GitHub Environments (approval gates)

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

---

## Branch Protection Rules for `main`

Navigate to: **GHA-Dynamics → Settings → Branches → Add rule for `main`**

Recommended settings:
- ✅ Require a pull request before merging
- ✅ Require status checks to pass
- ✅ Require branches to be up to date before merging
- ✅ Do not allow bypassing the above settings

> The merge of a `feature/*` PR to `main` is what triggers Pipeline 2 (`deploy-prod.yml`). Branch protection ensures this only happens after UAT is green and a human reviews the PR.
