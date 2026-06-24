# GHA-Dynamics — Power Platform CI/CD Pipeline

Enterprise-grade GitHub Actions pipeline for Microsoft Power Platform. Thin caller repo that delegates all build and deploy logic to [GHA-CICD-Core](https://github.com/ppudot2-cloud/GHA-CICD-Core).

---

## Two-Pipeline Architecture

**Pipeline 1 — `build-and-deploy.yml`**
Triggered by push to `feature/**` branch or `workflow_dispatch`. Export → Build (per solution, parallel) → Deploy Dev / Intg / UAT / FRS / Perf (all parallel) → Create PR to main.

**Pipeline 2 — `deploy-prod.yml`**
Triggered automatically when `pipeline-context.json` is pushed to `main` (i.e., when the Pipeline 1 PR is merged). Reads `pipeline-context.json` → Deploy UAT (re-validation gate) → Deploy Prod.

```
Pipeline 1:  push/dispatch → Export → Build × N → Dev ┐
                                                  Intg │ parallel
                                                  UAT  ├ → create PR → main
                                                  FRS  │
                                                  Perf ┘

Pipeline 2:  pipeline-context.json pushed to main → read context → UAT gate → Deploy UAT → Prod gate → Deploy Prod
```

---

## Repository Structure

```
GHA-Dynamics/
├── .github/
│   ├── workflows/
│   │   ├── build-and-deploy.yml    # Pipeline 1
│   │   ├── deploy-prod.yml         # Pipeline 2
│   │   ├── export-solution.yml     # Export from sandbox
│   │   ├── pr-validation.yml       # Build-only PR check
│   │   └── test-servicenow.yml     # ServiceNow flow simulation
│   └── config/
│       └── project-vars.yml        # Project-specific variable overrides
├── solutions.json                  # Solution registry — name, folder, deploy order
├── pipeline-context.json           # Cross-pipeline handoff — written by Pipeline 1 to the feature branch
├── src/solutions/{Name}/           # Unpacked solution source
├── config/{Name}/data-schema.xml   # Config migration schema (optional)
├── deployment-settings/
│   └── {env}/{Name}.json           # Per-environment variable overrides
└── scripts/
    └── simulate-pipeline.py        # Local dry-run simulation
```

---

## Quick Start

1. Set up Azure OIDC + Key Vault → see [ENTERPRISE_DEVSECOPS_GUIDE.md](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/ENTERPRISE_DEVSECOPS_GUIDE.md)
2. Configure GitHub environments, secret, and variables → see [QUICK_START.md](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/QUICK_START.md)
3. Edit `solutions.json` with your solution names
4. Run `build-and-deploy.yml` with `mock_deploy: true` to validate the wiring
5. Merge the created PR → Pipeline 2 fires automatically

---

## Documentation

All documentation lives in [GHA-CICD-Core/docs/](https://github.com/ppudot2-cloud/GHA-CICD-Core/tree/main/docs):

| Document | Description |
|---|---|
| [gha_cicd_e2e_flow.html](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/gha_cicd_e2e_flow.html) | Interactive diagram of the complete pipeline flow |
| [PIPELINE_REFERENCE.md](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/PIPELINE_REFERENCE.md) | Every workflow, action, script, and config file explained |
| [ENTERPRISE_DEVSECOPS_GUIDE.md](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/ENTERPRISE_DEVSECOPS_GUIDE.md) | Azure setup, OIDC, Key Vault, federated credentials |
| [QUICK_START.md](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/QUICK_START.md) | Step-by-step first pipeline run |
| [SECRETS_SETUP_GUIDE.md](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/SECRETS_SETUP_GUIDE.md) | GitHub secrets and variables reference |
| [ENTERPRISE_IMPLEMENTATION_GUIDE.md](https://github.com/ppudot2-cloud/GHA-CICD-Core/blob/main/docs/ENTERPRISE_IMPLEMENTATION_GUIDE.md) | Step-by-step production rollout — what to configure, what simulations to retire |

---

## Key Design Decisions

**Sequential imports within each environment** — Dataverse cannot process parallel solution imports to the same environment. `deploy-all-solutions` always imports solutions one at a time in `deployOrder` sequence.

**Parallel across environments** — Pipeline 1 deploys Dev, Intg, UAT, FRS, and Perf simultaneously. Each environment is independent and can proceed without waiting for others.

**Zero long-lived secrets in GitHub** — Only `GHA_CORE_PAT` is stored as a GitHub Secret. All Power Platform credentials are fetched at runtime from Azure Key Vault via OIDC.

**Mock deploy** — Set `mock_deploy: true` to simulate the entire pipeline (build, Solution Checker, deploy) without connecting to Dataverse, Azure, or JFrog. Every step runs; nothing is imported.

**Inline rollback** — When `enable_backup=true`, the pipeline exports the currently installed solution before importing. If the import fails, it automatically re-imports the backup — no separate rollback workflow needed.

