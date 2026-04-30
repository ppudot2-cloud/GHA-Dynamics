# GitHub Actions — Step-by-Step Run Guide

> **Repo:** GHA-Dynamics (private GitHub account)  
> **Goal:** Push the sample 3-solution repo to GitHub and execute the full Release Pipeline end-to-end with `mock-deploy=true` — no actual Dataverse imports are performed.

---

## Before You Start — Choose Your Path

The deploy jobs always run a `who-am-i` step to validate SPN connectivity, even when `mock-deploy=true`. This means you need one of the following:

| Path | What you need | When to use |
|---|---|---|
| **Path A — Full simulation with real PP credentials** | Azure AD App Registration + 5 real Dataverse environments (trial/dev tenants are fine) | You want to validate end-to-end auth + the complete pipeline |
| **Path B — Code-only simulation (no PP credentials)** | Nothing extra — apply a 3-line patch to skip auth in mock mode | You just want to see the GitHub Actions DAG run green without any PP access |

This guide covers **both paths**. Start with the steps in sections 1–3 (they're identical), then follow your chosen path from section 4 onward.

---

## Section 1 — Create the GitHub Repo

### 1.1 Create a new private repo

1. Go to [github.com](https://github.com) → **+** (top right) → **New repository**
2. Fill in:
   - **Repository name:** `GHA-Dynamics` (or any name you prefer)
   - **Visibility:** Private
   - **Initialize this repository:** ❌ Leave unchecked (you're pushing existing code)
3. Click **Create repository**
4. Copy the repo URL shown (e.g. `https://github.com/YOUR_USERNAME/GHA-Dynamics.git`)

### 1.2 Push the local repo to GitHub

Open a terminal in your `GHA-Dynamics` folder:

```bash
cd /path/to/GHA-Dynamics

# Initialize git if not already done
git init
git add .
git commit -m "feat: initial multi-solution pipeline setup (CoreSolution + ExtensionA + ExtensionB)"

# Add the remote and push
git remote add origin https://github.com/YOUR_USERNAME/GHA-Dynamics.git
git branch -M main
git push -u origin main
```

After the push, visit your repo on GitHub → confirm you can see `.github/workflows/`, `src/solutions/`, `deployment-settings/`, and `config/`.

---

## Section 2 — Enable GitHub Actions

1. In your repo, click **Actions** (top tab)
2. If prompted with "Workflows aren't running", click **I understand my workflows, go ahead and enable them**
3. You should now see the 6 workflow files listed on the left sidebar

> **Free account note:** Private repos get 2,000 Actions minutes/month on the free tier. Each full mock-deploy pipeline run uses roughly 15–25 minutes. If you plan to run it repeatedly, consider using [self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners) to avoid consuming quota.

---

## Section 3 — Create GitHub Environments

The pipeline uses 5 environments. You must create them in GitHub first, and add protection rules to the gated ones so approval prompts appear.

### 3.1 Navigate to Environments

**Settings** → **Environments** → **New environment**

### 3.2 Create each environment

Create these 5 environments **exactly as named** (case-sensitive — the workflows use these names):

| Environment | Protection rule | Required reviewers |
|---|---|---|
| `Dev` | None | — |
| `Intg` | ✅ Required reviewers | Add yourself (your GitHub username) |
| `UAT` | ✅ Required reviewers | Add yourself |
| `Perf` | ✅ Required reviewers | Add yourself |
| `Prod` | ✅ Required reviewers | Add yourself |

**For each gated environment (Intg / UAT / Perf / Prod):**
1. Click **New environment** → type the name → **Configure environment**
2. Check **Required reviewers** → type your GitHub username → **Save protection rules**

> The "Required reviewers" rule is what makes the gate jobs pause and wait for your approval. Without it the gate jobs auto-pass immediately.

---

## Section 4A — Path A: Full Simulation (Real PP Credentials)

> Skip to **Section 4B** if you're doing the code-only path.

### 4A.1 Create an Azure AD App Registration (Service Principal)

You need one SPN that has access to all your Power Platform environments.

1. Go to [portal.azure.com](https://portal.azure.com) → **Azure Active Directory** → **App registrations** → **New registration**
2. Name: `GHA-Dynamics-Pipeline` → **Register**
3. Note down:
   - **Application (client) ID** → this is your `APP_ID`
   - **Directory (tenant) ID** → this is your `TENANT_ID`
4. Go to **Certificates & secrets** → **New client secret** → add description, set expiry → **Add**
5. Copy the **Value** immediately → this is your `CLIENT_SECRET`

### 4A.2 Grant the SPN access to each Power Platform environment

In each of your 5 environments (Dev, Intg, UAT, Perf, Prod):

1. Go to [make.powerapps.com](https://make.powerapps.com) → select the environment
2. **Settings** → **Users + permissions** → **Application users** → **New app user**
3. Search for your app registration by name → select it
4. Assign the **System Administrator** security role → **Save**

### 4A.3 Add secrets to GitHub

Navigate to your repo: **Settings** → **Secrets and variables** → **Actions** → **Secrets** → **New repository secret**

Add these 3 secrets:

| Secret name | Value |
|---|---|
| `APP_ID` | Application (client) ID from Azure AD |
| `CLIENT_SECRET` | Client secret value from Azure AD |
| `TENANT_ID` | Directory (tenant) ID from Azure AD |

> These are **repository secrets**, not environment secrets. The reusable workflows inherit them via `secrets: inherit`.

### 4A.4 Add variables to GitHub

**Settings** → **Secrets and variables** → **Actions** → **Variables** → **New repository variable**

Add these variables with the actual URLs of your Power Platform environments:

| Variable name | Value example | Description |
|---|---|---|
| `PP_DEV_URL` | `https://your-dev-env.crm.dynamics.com` | Dev environment URL |
| `PP_INTG_URL` | `https://your-intg-env.crm.dynamics.com` | Integration environment URL |
| `PP_UAT_URL` | `https://your-uat-env.crm.dynamics.com` | UAT environment URL |
| `PP_PERF_URL` | `https://your-perf-env.crm.dynamics.com` | Performance environment URL |
| `PP_PROD_URL` | `https://your-prod-env.crm.dynamics.com` | Production environment URL |

> Find your environment URL: [make.powerapps.com](https://make.powerapps.com) → select environment → **Settings** → **Session details** → Instance URL.

**Optional variables** (the workflow falls back to sensible defaults if absent):

| Variable name | Default | Description |
|---|---|---|
| `PP_CHECKER_GEO` | `UnitedStates` | Solution Checker geography |

Now skip to **Section 5** to trigger the workflow.

---

## Section 4B — Path B: Code-Only Simulation (No PP Credentials)

This path patches `_reusable-deploy.yml` to skip auth steps when `mock-deploy=true`, allowing the full GitHub Actions DAG to run green without needing any Power Platform environments or Azure AD credentials.

### 4B.1 Apply the mock-deploy auth skip patch

Open `.github/workflows/_reusable-deploy.yml` and make these two changes:

**Change 1 — Make `who-am-i` conditional on mock-deploy being false**

Find the `who-am-i` step (around line 168) and add an `if:` condition:

```yaml
- name: Validate connection — who-am-i
  id: who-am-i
  if: inputs.mock-deploy == false          # ← ADD THIS LINE
  uses: microsoft/powerplatform-actions/who-am-i@v1
  with:
    environment-url: ${{ inputs.environment-url }}
    app-id:          ${{ secrets.APP_ID }}
    client-secret:   ${{ secrets.CLIENT_SECRET }}
    tenant-id:       ${{ secrets.TENANT_ID }}
```

**Change 2 — Make `backup-environment` conditional** (it also runs before mock-deploy check)

Find the `backup-environment` step and ensure it has:
```yaml
if: inputs.enable-backup == true && inputs.mock-deploy == false
```

### 4B.2 Add placeholder secrets

GitHub requires secrets referenced in a workflow to exist, even if the step that uses them is skipped. Add these 3 placeholder secrets:

**Settings** → **Secrets and variables** → **Actions** → **Secrets** → **New repository secret**

| Secret name | Value (placeholder) |
|---|---|
| `APP_ID` | `mock-app-id-not-used` |
| `CLIENT_SECRET` | `mock-secret-not-used` |
| `TENANT_ID` | `mock-tenant-not-used` |

### 4B.3 Add placeholder variables

**Settings** → **Secrets and variables** → **Actions** → **Variables** → **New repository variable**

| Variable name | Value (placeholder) |
|---|---|
| `PP_DEV_URL` | `https://mock-dev.crm.dynamics.com` |
| `PP_INTG_URL` | `https://mock-intg.crm.dynamics.com` |
| `PP_UAT_URL` | `https://mock-uat.crm.dynamics.com` |
| `PP_PERF_URL` | `https://mock-perf.crm.dynamics.com` |
| `PP_PROD_URL` | `https://mock-prod.crm.dynamics.com` |

### 4B.4 Commit and push the patch

```bash
git add .github/workflows/_reusable-deploy.yml
git commit -m "fix: skip auth steps when mock-deploy=true (code-only simulation)"
git push
```

---

## Section 5 — Trigger the Release Pipeline

### 5.1 Open the workflow

1. In your repo, click **Actions**
2. In the left sidebar, click **Release Pipeline**
3. Click **Run workflow** (top right of the workflow list)

### 5.2 Fill in the inputs

A form will appear. Fill it in as follows for the full mock simulation:

| Input | Value | Notes |
|---|---|---|
| **Solutions** | `all` | Runs CoreSolution → ExtensionA → ExtensionB |
| **Target environments** | `all` | Runs the full chain Dev → Intg → UAT → Perf → Prod |
| **Enable backup** | `false` | No backup needed in simulation |
| **Enable blocking check** | `false` | Skip async-operation check |
| **Enable version compare** | `false` | Skip version comparison |
| **mock-deploy** | ✅ `true` | ← The key toggle — skips all actual imports |
| **trigger-upgrade** | `false` | Use in-place update pattern |
| **Import config data** | `false` | Skip data import in simulation |

3. Click **Run workflow** → the green button

### 5.3 Watch the pipeline start

The workflow will appear in the list within a few seconds. Click on it to open the run view. You'll see the job DAG:

```
🔍 Resolve Solutions
        │
        ▼
┌──────────────────────────────────────────┐
│  🏗️ Build | CoreSolution   (parallel)    │
│  🏗️ Build | ExtensionA     (parallel)    │
│  🏗️ Build | ExtensionB     (parallel)    │
└──────────────────────────────────────────┘
        │
        ▼
🚀 Dev [Unmanaged] | CoreSolution  ─┐
🚀 Dev [Unmanaged] | ExtensionA    ─┤  (sequential, one after another)
🚀 Dev [Unmanaged] | ExtensionB    ─┘
        │
        ▼
🔐 Gate | Intg   ← WAITING FOR YOUR APPROVAL
        │
       ...
```

---

## Section 6 — Approve the Gates

Each gate (Intg, UAT, Perf, Prod) pauses the pipeline and waits for a human approval. You'll get email notifications to your GitHub account email.

### 6.1 Approve a gate

**Option A — From the Actions run page:**
1. Open the run → find the orange `🔐 Gate | Intg` job (it shows a yellow clock icon = waiting)
2. Click the job → click **Review deployments**
3. Check the box next to `Intg` → click **Approve and deploy**

**Option B — From the email notification:**
1. Open the notification email from GitHub → click **Review pending deployments**
2. Approve directly from the browser

### 6.2 Repeat for each environment

After approving Intg, the pipeline deploys to Intg, then pauses again at the UAT gate. Repeat the approval step for UAT → Perf → Prod.

**Full approval sequence:**
```
Dev auto-deploys → [Approve Intg] → Intg deploys → [Approve UAT] → UAT deploys
  → [Approve Perf] → Perf deploys → [Approve Prod] → Prod deploys → Summary ✅
```

---

## Section 7 — Read the Results

### 7.1 Pipeline Summary tab

After the pipeline completes, click the last job **📋 Pipeline Summary** → click the **Summary** tab at the top. You'll see a table like:

| Stage | Environment | Result |
|---|---|---|
| 🔍 Resolve | — | ✅ |
| 🏗️ Build (×3) | — | ✅ |
| 🚀 Deploy | Dev | ✅ |
| 🔐 Gate | Intg | ✅ |
| 🚀 Deploy | Intg | ✅ |
| ... | ... | ... |
| 🚀 Deploy | Prod | ✅ |

### 7.2 Per-job step detail

Click any individual job (e.g. `🚀 Dev [Unmanaged] | CoreSolution`) to expand its steps. You'll see:
- **Validate connection (who-am-i)** — confirms SPN auth (Path A) or skipped (Path B)
- **Resolve settings file** — shows which `deployment-settings/dev/CoreSolution.json` was picked
- **Mock deploy notice** — confirms no actual import ran

### 7.3 Artifact upload

In the Build jobs, the `actions/upload-artifact@v4` step uploads the packed solution ZIPs. You can download them from the **Summary** page → **Artifacts** section at the bottom. This confirms the pack step ran correctly.

---

## Section 8 — Common Issues & Fixes

| Symptom | Cause | Fix |
|---|---|---|
| Workflow doesn't appear in Actions | Workflow YAML has a syntax error | Run `yamllint .github/workflows/release-pipeline.yml` locally to check |
| `Error: No solutions found in src/solutions/` | `src/solutions/` wasn't pushed | Run `git ls-files src/solutions/` to verify, then push |
| Gate job fails immediately (no pause) | Environment has no required reviewer set | Go to Settings → Environments → add yourself as reviewer |
| Build fails on `check-solution@v1` | Needs `APP_ID` / `CLIENT_SECRET` / `TENANT_ID` | Solution Checker always requires auth — use Path A or add placeholders |
| `Resource not accessible by integration` | Workflow permissions too restrictive | Settings → Actions → General → set Workflow permissions to **Read and write** |
| `Context access might be invalid: inputs.mock-deploy` | Triggered by PR (no inputs) | PR triggers default all inputs to empty = falsy, so mock-deploy=false. Use `workflow_dispatch` instead |

---

## Quick Reference — What Each Input Does

| Input | Default | Effect when true |
|---|---|---|
| `solutions` | `all` | Controls which solutions are built and deployed |
| `target-environments` | `all` | Can limit to `dev`, `dev-intg`, or `dev-intg-uat` |
| `enable-backup` | `true` | Calls `backup-environment@v1` before each import |
| `enable-blocking-check` | `true` | Aborts if PP has in-progress async operations |
| `enable-version-compare` | `true` | Ensures version in previous env matches before promoting |
| `mock-deploy` | `false` | Skips import, publish, activate, data import — runs all checks only |
| `trigger-upgrade` | `false` | Uses holding-solution upgrade pattern (safer for managed layers) |
| `import-config-data` | `false` | Imports CMT reference data after each solution |
