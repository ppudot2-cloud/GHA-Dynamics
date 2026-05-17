# Quick Start Guide
## Power Platform CI/CD — First Pipeline Run

> This guide takes you from zero to a running pipeline. For full enterprise setup (Azure OIDC, Key Vault, multi-environment hardening) see [ENTERPRISE_DEVSECOPS_GUIDE.md](./ENTERPRISE_DEVSECOPS_GUIDE.md).

---

## Prerequisites

Before starting you need:

- Two GitHub repositories in your org: `GHA-Core` and `GHA-Dynamics`
- Azure subscription with an App Registration (for OIDC + Key Vault)
- Azure Key Vault containing `pp-app-id`, `pp-client-secret`, `pp-tenant-id`
- Power Platform environments: Dev, Intg, UAT, FRS, Perf, Prod (and optionally a Sandbox)
- Power Platform application user registered in each environment

For instructions on creating all of the above see [ENTERPRISE_DEVSECOPS_GUIDE.md](./ENTERPRISE_DEVSECOPS_GUIDE.md).

---

## Step 1 — Create GitHub Environments

Navigate to **GHA-Dynamics → Settings → Environments** and create these six environments (names are case-sensitive):

| Environment | Required Reviewers | Notes |
|---|---|---|
| `Dev` | Optional | Auto-deploys without approval |
| `Intg` | Recommended | Integration/QA lead |
| `UAT` | Recommended | QA lead |
| `FRS` | Optional | Functional review team |
| `Perf` | Optional | Performance team |
| `Prod` | Required | Release manager — also applies to rollbacks |

---

## Step 2 — Set GitHub Secret

**GHA-Dynamics → Settings → Secrets and variables → Actions → Secrets**

| Secret | Value |
|---|---|
| `GHA_CORE_PAT` | Personal Access Token with `repo` scope (needs access to the private GHA-Core repo) |

---

## Step 3 — Set GitHub Variables

**GHA-Dynamics → Settings → Secrets and variables → Actions → Variables**

| Variable | Example Value | Required |
|---|---|---|
| `AZURE_CLIENT_ID` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | ✅ |
| `AZURE_TENANT_ID` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | ✅ (your real tenant, not Contoso) |
| `AZURE_SUBSCRIPTION_ID` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | ✅ |
| `AZURE_KEY_VAULT_NAME` | `kv-pp-cicd` | ✅ |
| `PP_SDBX_URL` | `https://yourorg-sdbx.crm.dynamics.com` | ✅ |
| `PP_DEV_URL` | `https://yourorg-dev.crm.dynamics.com` | ✅ |
| `PP_INTG_URL` | `https://yourorg-intg.crm.dynamics.com` | ✅ |
| `PP_UAT_URL` | `https://yourorg-uat.crm.dynamics.com` | ✅ |
| `PP_FRS_URL` | `https://yourorg-frs.crm.dynamics.com` | ✅ |
| `PP_PERF_URL` | `https://yourorg-perf.crm.dynamics.com` | ✅ |
| `PP_PROD_URL` | `https://yourorg.crm.dynamics.com` | ✅ |
| `JFROG_URL` | `https://yourorg.jfrog.io/artifactory` | Optional |
| `JFROG_REPO` | `powerplatform-solutions` | Optional |

---

## Step 4 — Configure solutions.json

Edit `solutions.json` in the root of GHA-Dynamics to describe your solutions:

```json
{
  "solutions": [
    {
      "name": "MySolution",
      "folder": "src/solutions/MySolution",
      "deployOrder": 1,
      "dependsOn": [],
      "checkerGeo": "UnitedStates",
      "dataSchemaFile": "",
      "deploymentSettings": {
        "dev":  "deployment-settings/dev/MySolution.json",
        "intg": "deployment-settings/intg/MySolution.json",
        "uat":  "deployment-settings/uat/MySolution.json",
        "frs":  "deployment-settings/frs/MySolution.json",
        "perf": "deployment-settings/perf/MySolution.json",
        "prod": "deployment-settings/prod/MySolution.json"
      }
    }
  ]
}
```

Create deployment settings files at the paths listed. Minimum valid content:

```json
{
  "EnvironmentVariables": [],
  "ConnectionReferences": []
}
```

---

## Step 5 — Run the Pipeline (Mock Mode First)

Always run mock mode first to validate the entire wiring without touching Dataverse.

1. Go to **GHA-Dynamics → Actions → build-and-deploy.yml**
2. Click **Run workflow**
3. Set `mock_deploy: true`
4. Click **Run workflow**

Watch the jobs:
- `setup` — reads solutions.json, builds matrix
- `stage-export` — simulates export (no sandbox connection)
- `stage-build` — simulates build per solution (no PAC CLI)
- `deploy-dev`, `deploy-intg`, `deploy-uat`, `deploy-frs`, `deploy-perf` — all run in parallel, all simulated
- `create-main-pr` — creates a real PR on GitHub (this step runs for real even in mock mode)

Check the **Summary** tab for the consolidated pipeline report.

---

## Step 6 — Approve the PR and Trigger Pipeline 2

After Pipeline 1 succeeds and creates a PR:

1. Navigate to the PR created by `create-main-pr`
2. Review and merge it into `main`
3. Pipeline 2 (`deploy-prod.yml`) triggers automatically
4. Watch `deploy-uat` — approve if an environment gate is configured
5. Watch `deploy-prod` — approve when prompted

Both `deploy-uat` and `deploy-prod` are simulated in mock mode (if `mock_deploy` was set in Pipeline 1, the `pipeline-context.json` carries that setting — but Pipeline 2 has its own `mock_deploy` input for manual triggers).

---

## Step 7 — Run a Real Deploy

Once mock mode is green, run a real deploy:

1. Go to **build-and-deploy.yml → Run workflow**
2. Leave `mock_deploy: false` (the default)
3. Click **Run workflow**
4. Approve environment gates as they pause

Each environment gate pauses the pipeline and sends an email/notification to the configured required reviewers. One approval covers all solutions in that environment.

---

## Running the Export Workflow

To export solutions from your sandbox:

1. Go to **export-solution.yml → Run workflow**
2. Leave `solution_name` empty to export all, or enter a specific solution name
3. Set `mock_deploy: true` for a dry-run (no sandbox connection)
4. The workflow commits the exported source to a feature branch and optionally creates a PR

---

## Rolling Back an Environment

If a deployment goes wrong:

1. Go to **rollback.yml → Run workflow**
2. Select the `target-environment`
3. Enter the `solution-name` to roll back
4. Enter the `run-number` of the deployment to roll back FROM
5. Type `CONFIRM` in the confirm field
6. Click **Run workflow**

The rollback re-imports the pre-deploy backup ZIP. Backups are only available if `enable_backup: true` was set during the original deploy.

---

## Local Dry-Run Simulation

Simulate the pipeline locally without GitHub Actions or Dataverse access:

```bash
# Full simulation — all solutions, all environments
python3 scripts/simulate-pipeline.py --solutions all --run-number 42

# Specific solutions
python3 scripts/simulate-pipeline.py --solutions CoreSolution,ExtensionA --run-number 99

# Target specific environments
python3 scripts/simulate-pipeline.py --solutions all --target-envs DEV,INTG --run-number 42
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `AADSTS700016: Application not found in directory 'Contoso'` | `AZURE_TENANT_ID` variable is wrong — pointing to demo tenant | Update `AZURE_TENANT_ID` GitHub variable to your real Azure AD Tenant ID |
| `The term '.ci/templates/steps/dynamics/...' is not recognized` | Old script path reference | Verify all scripts reference `.ci/.github/scripts/dynamics/` |
| `fatal: could not read Username for 'https://github.com'` | `GHA_CORE_PAT` not set or expired | Update the `GHA_CORE_PAT` secret |
| `Login failed: The process '/usr/bin/az' failed` | Azure OIDC misconfigured | Check federated credentials on App Registration match your repo/environment names exactly |
| `who-am-i` step fails | PP service principal not registered in the target environment | Add the App Registration as Application User with System Administrator role |
| `Solution package type did not match requested type` | `<Managed>0</Managed>` tag present in Solution.xml | Handled automatically by `Remove-ManagedTag.ps1` — check the pack step ran |
| Pipeline 2 does not trigger after PR merge | `pipeline-context.json` not in the merged commit | Confirm `create-main-pr` job succeeded and committed the file to the feature branch |
