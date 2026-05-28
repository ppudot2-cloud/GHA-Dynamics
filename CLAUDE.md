# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Thin **caller** workflows for the GHA-Core reusable workflow library. GHA-Dynamics exposes `workflow_dispatch` inputs, reads `vars.*` repository variables (which cannot cross repo boundaries), and forwards everything to GHA-Core. **All build, deploy, test, lint, and rollback logic lives in GHA-Core — edit there, not here.**

## Repository structure (3 folders only)

```
.github/
  config/
    project-vars.yml          # Project-specific variable overrides (merged on top of GHA-Core global-vars.yml)
  workflows/
    build-and-deploy.yml      # Pipeline 1: Export → Build → Dev/Intg/UAT/FRS/Perf → create PR
    deploy-prod.yml           # Pipeline 2: UAT re-validation → Prod (auto-triggered on PR merge)
    export-solution.yml       # Ad-hoc: export from sandbox → branch → PR

src/
  solutions/{SolutionName}/
    [solution source files]                        # Unpacked PP solution XML/JSON
    deployment-settings-{env}.json                 # Per-env variable overrides (dev/intg/uat/frs/perf/prod)
    config-data-schema.xml                         # Config Migration schema XML (empty if unused)

solutions.json                # Solution registry — single source of truth
pipeline-context.json         # Runtime handshake written by Pipeline 1, read by Pipeline 2
```

## Solution configuration convention

Each solution's deployment-settings and config-data schema live **inside its own folder**:

```
src/solutions/CoreSolution/
  [source files…]
  deployment-settings-dev.json
  deployment-settings-intg.json
  deployment-settings-uat.json
  deployment-settings-frs.json
  deployment-settings-perf.json
  deployment-settings-prod.json
  config-data-schema.xml
```

`solutions.json` references these paths as `src/solutions/{Name}/deployment-settings-{env}.json`.

## Local simulation

All tooling lives in GHA-Core. After checking out GHA-Core to `.ci/`:

```bash
python3 .ci/.github/scripts/dynamics/simulate-pipeline.py --solutions all --run-number 42
```

## Workflows and what they delegate

| Workflow | Trigger | GHA-Core reusables called |
|---|---|---|
| `build-and-deploy.yml` | `workflow_dispatch` or push to `feature/**` | `_reusable-lint`, `_stage-export`, `_stage-build`, `pipeline-test` (optional) |
| `deploy-prod.yml` | push to `main` (pipeline-context.json changes) or `workflow_dispatch` | deploy-all-solutions composite |
| `export-solution.yml` | `workflow_dispatch` | reveille composite |

## Pipeline flow (build-and-deploy.yml)

```
setup
  → [optional] pr-validation    (run_pr_validation=true or push event)
  → [optional] pipeline-tests   (run_pipeline_tests=true)
  → lint-config                 (calls GHA-Core _reusable-lint.yml — blocks on failure)
  → stage-export                (calls GHA-Core _stage-export.yml)
  → stage-build                 (calls GHA-Core _stage-build.yml)
  → deploy-dev / deploy-intg / deploy-uat / deploy-frs / deploy-perf  (parallel, each gated)
  → create-main-pr              (after UAT passes)
```

Merging the PR triggers `deploy-prod.yml`: UAT re-validation → Prod.

## Key environment variables

| Variable | Scope | Purpose |
|---|---|---|
| `PP_DEV_URL` … `PP_PROD_URL`, `PP_SDBX_URL` | Repo | PP environment URLs |
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Repo | OIDC identity |
| `AZURE_KEY_VAULT_NAME` | Repo | Key Vault holding PP credentials |
| `ENABLE_ROLLBACK` | **Per environment** | `true` = auto-backup + auto-restore on import failure |
| `SKIP_UAT` | Repo (break-glass) | `true` = Pipeline 2 skips UAT re-validation |
| `SERVICENOW_ENABLED` | Repo or env | ServiceNow CR integration toggle |
| `JFROG_URL`, `JFROG_REPO` | Repo | JFrog Artifactory |

## Rollback

- **Auto-rollback**: `ENABLE_ROLLBACK=true` on any GitHub Environment → pipeline backs up and auto-restores on failure
- **Manual rollback**: trigger `GHA-Core/.github/workflows/rollback.yml` from GHA-Core's Actions tab

## UAT bypass (break-glass)

If UAT is broken and blocking Prod:
- Option A: manually dispatch `deploy-prod.yml` with `skip_uat=true`
- Option B: set repo variable `SKIP_UAT=true` (works even on auto-trigger) — remember to unset after the emergency deployment

## Required secrets

- `GHATOKEN` — PAT for cross-repo checkout and PR creation
- `MAIL_PASSWORD` — (optional) SMTP password for failure notifications
- PP credentials stored in Azure Key Vault (never as GitHub Secrets)
