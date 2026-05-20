# Documentation

All pipeline documentation has moved to **GHA-Core** — the shared library repository.

This keeps documentation co-located with the reusable workflows, composite actions, and scripts it describes, and ensures every GHA-Dynamics project (across the organisation) links to one authoritative source.

## Where to find the docs

Navigate to `docs/` in the [GHA-Core repository](https://github.com/ppudot2-cloud/GHA-Core/tree/main/docs):

| Document | Description |
|---|---|
| [QUICK_START.md](https://github.com/ppudot2-cloud/GHA-Core/blob/main/docs/QUICK_START.md) | First pipeline run — mock mode through to real deploy |
| [PIPELINE_REFERENCE.md](https://github.com/ppudot2-cloud/GHA-Core/blob/main/docs/PIPELINE_REFERENCE.md) | Every workflow, action, script, and config file explained |
| [SECRETS_SETUP_GUIDE.md](https://github.com/ppudot2-cloud/GHA-Core/blob/main/docs/SECRETS_SETUP_GUIDE.md) | All GitHub secrets, variables, AKV secrets, and environment variables |
| [ENTERPRISE_DEVSECOPS_GUIDE.md](https://github.com/ppudot2-cloud/GHA-Core/blob/main/docs/ENTERPRISE_DEVSECOPS_GUIDE.md) | Azure OIDC, Key Vault, federated credentials, full enterprise setup |
| [ENTERPRISE_IMPLEMENTATION_GUIDE.md](https://github.com/ppudot2-cloud/GHA-Core/blob/main/docs/ENTERPRISE_IMPLEMENTATION_GUIDE.md) | Step-by-step guide to production deployment — what to configure, what simulations to retire |
| [gha_cicd_e2e_flow.html](https://github.com/ppudot2-cloud/GHA-Core/blob/main/docs/gha_cicd_e2e_flow.html) | Interactive end-to-end pipeline flow diagram |

## Project-specific configuration

Documentation specific to **this project** lives here in GHA-Dynamics:

- [`solutions.json`](../solutions.json) — solution registry and deploy order
- [`deployment-settings/`](../deployment-settings/) — per-environment variable overrides
- [`CLAUDE.md`](../CLAUDE.md) — guidance for AI-assisted development in this repo
