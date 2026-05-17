# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Thin **caller** workflows for the GHA-Core reusable workflow library. GHA-Dynamics exposes `workflow_dispatch` inputs, reads `vars.*` repository variables (which cannot cross repo boundaries), and forwards everything to GHA-Core. **All build and deploy logic lives in GHA-Core — edit there, not here.**

## Local simulation

```bash
# Full pipeline dry-run (no Dataverse changes, no git push, no JFrog upload)
python3 scripts/simulate-pipeline.py --solutions all --run-number 42

# Specific solutions or environments
python3 scripts/simulate-pipeline.py --solutions "CoreSolution,ExtensionA" --target-envs "dev,intg"

# Compute the deploy matrix (outputs GitHub Actions matrix JSON to stdout)
python3 scripts/compute-solutions.py --selection all --event workflow_dispatch
```

## Repository structure

```
solutions.json                    # Solution registry — single source of truth for name, folder, dependsOn, deploymentSettings paths
scripts/
  compute-solutions.py            # Reads solutions.json → topological sort → GITHUB_OUTPUT matrix JSON (called by workflows)
  simulate-pipeline.py            # Full local dry-run simulation of every pipeline stage
src/solutions/{SolutionName}/     # Unpacked solution source files
config/{SolutionName}/            # Configuration migration data schema XML per solution
deployment-settings/{env}/{SolutionName}.json  # Per-solution, per-environment variable overrides
.github/workflows/
  release-pipeline.yml            # Full promotion chain: PR / manual dispatch
  export-solution.yml             # Export sandbox → branch → PR
  deploy-dev.yml                  # Ad-hoc deploy to Dev only
  rollback.yml                    # Rollback a specific environment
```

## Workflows and what they delegate

| Workflow | Trigger | GHA-Core reusables called |
|---|---|---|
| `release-pipeline.yml` | PR to `main` or `workflow_dispatch` | `_reusable-build`, `_reusable-deploy`, `_reusable-jfrog` |
| `export-solution.yml` | `workflow_dispatch` | (inline PowerShell + PAC CLI steps) |
| `deploy-dev.yml` | `workflow_dispatch` | `_reusable-deploy-dev` |
| `rollback.yml` | `workflow_dispatch` | `_reusable-rollback` |

## Pipeline flow (release-pipeline.yml)

```
setup (compute-solutions.py) → build per solution (parallel)
  → deploy-dev (sequential, max-parallel:1)
  → gate-intg → deploy-intg (sequential)
  → gate-uat  → deploy-uat  (sequential)
  → gate-frs  → deploy-frs  (sequential)
  → gate-perf → deploy-perf (sequential)
  → gate-prod → deploy-prod (sequential, only after ALL solutions pass UAT)
```

Approval gates = GitHub Environment protection rules. Adding/removing required reviewers on a named environment controls which stages block for sign-off.

## solutions.json — key fields

- `dependsOn`: drives topological sort in `compute-solutions.py` → controls deploy order
- `deploymentSettings`: per-env JSON paths; passed to `_reusable-deploy` as `settings_file` input

## Required GitHub secrets and variables

**Secrets** (Settings → Secrets and variables → Actions → Secrets):
- `PP_APP_ID`, `PP_CLIENT_SECRET`, `PP_TENANT_ID` — service principal with Power Platform Administrator role on every environment

**Variables** (Settings → Secrets and variables → Actions → Variables):
- `PP_SDBX_URL`, `PP_DEV_URL`, `PP_INTG_URL`, `PP_UAT_URL`, `PP_FRS_URL`, `PP_PERF_URL`, `PP_PROD_URL`
- `PP_SOLUTION_NAME` (single-solution repos only), `PP_CHECKER_GEO`, `PP_DATA_SCHEMA_FILE`

**Environments** (Settings → Environments):
- `Dev`, `Intg`, `UAT`, `FRS`, `Perf`, `Prod` — each with required reviewers configured

## Constraints

- **Sequential imports are mandatory**: `max-parallel: 1` on all deploy jobs — Dataverse cannot process parallel solution imports
- **Solution Checker is always mandatory** in non-mock builds — no toggle to skip it
- **Mock mode**: pass `mock-deploy: true` at `workflow_dispatch` to simulate the full pipeline with no Dataverse changes; or run `simulate-pipeline.py` locally
- **Artifact storage**: JFrog Artifactory (not GitHub artifact storage) — build uploads after Solution Checker passes; all deploy environments download from JFrog
