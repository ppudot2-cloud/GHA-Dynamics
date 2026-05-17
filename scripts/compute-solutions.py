#!/usr/bin/env python3
"""
compute-solutions.py
====================
Reads solutions.json, resolves the user's selection, performs a topological
sort to honour dependency order, and writes GitHub Actions matrix JSON to
GITHUB_OUTPUT.

Called by: release-pipeline.yml, deploy-dev.yml

Usage
-----
  python3 scripts/compute-solutions.py \\
    --selection  "CoreSolution,ExtensionA"   # or "all" (default)
    --event      "workflow_dispatch"          # or "pull_request"
    --solutions-file  "solutions.json"        # default

GITHUB_OUTPUT keys written
--------------------------
  has-solutions   "true" | "false"
  build-matrix    JSON {include:[...]}  — all selected, for PARALLEL build
  deploy-matrix   JSON {include:[...]}  — topologically ordered, for SEQUENTIAL deploy
                  Items are flattened (no nested objects) so GitHub Actions
                  matrix variables like ${{ matrix.devSettings }} work directly.
"""

import argparse
import json
import os
import subprocess
import sys


# ─── Load & validate ────────────────────────────────────────────────────────

def load_solutions(path: str) -> dict[str, dict]:
    """Return {name: solution_dict} from solutions.json."""
    with open(path) as f:
        config = json.load(f)
    solutions = config.get("solutions", [])
    if not solutions:
        _error(f"No solutions defined in {path}")
    result = {}
    for s in solutions:
        name = s.get("name", "")
        if not name:
            _error(f"A solution entry is missing the 'name' field in {path}")
        if name in result:
            _error(f"Duplicate solution name '{name}' in {path}")
        result[name] = s
    return result


# ─── Selection helpers ───────────────────────────────────────────────────────

def detect_changed(all_solutions: dict) -> list[str]:
    """
    For pull_request events: return solution names whose source folders
    contain files that changed vs origin/main.
    """
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "origin/main...HEAD"],
            capture_output=True, text=True, check=True,
        )
        changed_files = set(result.stdout.strip().splitlines())
    except subprocess.CalledProcessError:
        _warning("Could not run git diff — defaulting to all solutions")
        return list(all_solutions.keys())

    hit = []
    for name, sol in all_solutions.items():
        folder = sol["folder"].rstrip("/") + "/"
        if any(f.startswith(folder) for f in changed_files):
            hit.append(name)

    if not hit:
        _notice("No solution source files changed in this PR")
    return hit


def expand_dependents(selected: list[str], all_solutions: dict) -> list[str]:
    """
    Expand selection to include any solution that depends (directly or
    transitively) on a solution already in the selection set.
    E.g. selecting CoreSolution forces ExtensionA (which depends on it)
    to also be selected — because ExtensionA must be rebuilt after a core change.
    """
    s_set = set(selected)
    changed = True
    while changed:
        changed = False
        for name, sol in all_solutions.items():
            if name not in s_set:
                if any(d in s_set for d in sol.get("dependsOn", [])):
                    s_set.add(name)
                    changed = True
    return list(s_set)


def expand_dependencies(requested: list[str], all_solutions: dict) -> list[str]:
    """
    Expand a manual selection to include any missing dependency so that
    the deploy ordering is valid.
    E.g. selecting only ExtensionA auto-adds CoreSolution.
    """
    s_set = set(requested)
    changed = True
    while changed:
        changed = False
        for name in list(s_set):
            for dep in all_solutions.get(name, {}).get("dependsOn", []):
                if dep not in s_set:
                    if dep not in all_solutions:
                        _warning(
                            f"Solution '{name}' declares dependency '{dep}' "
                            f"which is not in solutions.json — skipping"
                        )
                    else:
                        s_set.add(dep)
                        changed = True
    return list(s_set)


# ─── Topological sort ────────────────────────────────────────────────────────

def topo_sort(names: list[str], all_solutions: dict) -> list[str]:
    """
    Return names in deployment order: dependencies before dependents.
    Raises on circular dependencies.
    """
    names_set = set(names)
    visited: set[str] = set()
    in_stack: set[str] = set()   # for cycle detection
    order: list[str] = []

    def visit(n: str):
        if n in in_stack:
            _error(f"Circular dependency detected involving '{n}'")
        if n in visited:
            return
        in_stack.add(n)
        for dep in all_solutions.get(n, {}).get("dependsOn", []):
            if dep in names_set:
                visit(dep)
        in_stack.discard(n)
        visited.add(n)
        order.append(n)

    for n in names:
        visit(n)
    return order


# ─── Matrix flattening ───────────────────────────────────────────────────────

def flatten(sol: dict) -> dict:
    """
    Convert a solutions.json entry into a flat dict safe for use as a
    GitHub Actions matrix row.  Nested objects (deploymentSettings) are
    expanded to individual keys so expressions like ${{ matrix.devSettings }}
    work correctly in workflow with: blocks.
    """
    ds = sol.get("deploymentSettings", {})
    return {
        "name":           sol["name"],
        "folder":         sol["folder"],
        "dataSchemaFile": sol.get("dataSchemaFile", ""),
        # Per-environment deployment-settings paths
        "devSettings":    ds.get("dev",  ""),
        "intgSettings":   ds.get("intg", ""),
        "uatSettings":    ds.get("uat",  ""),
        "perfSettings":   ds.get("perf", ""),
        "prodSettings":   ds.get("prod", ""),
    }


# ─── Output helpers ──────────────────────────────────────────────────────────

def write_outputs(data: dict):
    path = os.environ.get("GITHUB_OUTPUT", "")
    text = "\n".join(f"{k}={v}" for k, v in data.items()) + "\n"
    if path:
        with open(path, "a") as f:
            f.write(text)
    else:
        print("[GITHUB_OUTPUT]")
        print(text)


def write_summary(lines: list[str]):
    path = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if path:
        with open(path, "a") as f:
            f.write("\n".join(lines) + "\n")


def _error(msg: str):
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(1)


def _warning(msg: str):
    print(f"::warning::{msg}", file=sys.stderr)


def _notice(msg: str):
    print(f"::notice::{msg}", file=sys.stderr)


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selection",      default="all",
                    help='Comma-separated solution names or "all"')
    ap.add_argument("--event",          default="workflow_dispatch",
                    help="GitHub event name (workflow_dispatch | pull_request)")
    ap.add_argument("--solutions-file", default="solutions.json")
    args = ap.parse_args()

    # Load registry
    if not os.path.exists(args.solutions_file):
        _error(
            f"'{args.solutions_file}' not found. "
            "Create this file at the repo root — see the template in the repo."
        )
    all_solutions = load_solutions(args.solutions_file)

    # ── Resolve selection ─────────────────────────────────────────────────────
    if args.event == "pull_request":
        # Auto-detect which solutions changed; expand to include their dependents
        changed  = detect_changed(all_solutions)
        selected = expand_dependents(changed, all_solutions)
        if changed and selected != changed:
            auto = [s for s in selected if s not in changed]
            _notice(f"Auto-included dependent solutions: {', '.join(auto)}")
    else:
        raw = args.selection.strip()
        if not raw or raw.lower() == "all":
            selected = list(all_solutions.keys())
        else:
            requested = [s.strip() for s in raw.split(",") if s.strip()]
            unknown = [s for s in requested if s not in all_solutions]
            if unknown:
                _error(
                    f"Unknown solution(s): {', '.join(unknown)}. "
                    f"Available: {', '.join(all_solutions.keys())}"
                )
            # Auto-include any missing dependencies
            selected  = expand_dependencies(requested, all_solutions)
            auto_deps = [s for s in selected if s not in requested]
            if auto_deps:
                _notice(
                    f"Auto-included missing dependencies: {', '.join(auto_deps)}"
                )

    # ── Nothing to do ─────────────────────────────────────────────────────────
    if not selected:
        _notice("No solutions selected or changed — nothing to build.")
        write_outputs({
            "has-solutions": "false",
            "build-matrix":  '{"include":[]}',
            "deploy-matrix": '{"include":[]}',
        })
        return

    # ── Sort and flatten ──────────────────────────────────────────────────────
    ordered       = topo_sort(selected, all_solutions)
    build_matrix  = {"include": [flatten(all_solutions[n]) for n in selected]}
    deploy_matrix = {"include": [flatten(all_solutions[n]) for n in ordered]}

    # ── Console output (visible in Actions log) ───────────────────────────────
    print(f"Selected  ({len(selected)}): {', '.join(selected)}")
    print(f"Deploy order: {' → '.join(ordered)}")

    # ── Step summary ──────────────────────────────────────────────────────────
    rows = [
        "## 🔍 Solution Selection",
        "",
        "| Deploy Order | Solution | Depends On |",
        "| :---: | --- | --- |",
    ]
    for i, n in enumerate(ordered, 1):
        deps = all_solutions[n].get("dependsOn") or ["—"]
        rows.append(f"| {i} | `{n}` | {', '.join(deps)} |")
    rows.append("")
    write_summary(rows)

    # ── Write GITHUB_OUTPUT ───────────────────────────────────────────────────
    write_outputs({
        "has-solutions": "true",
        "build-matrix":  json.dumps(build_matrix),
        "deploy-matrix": json.dumps(deploy_matrix),
    })


if __name__ == "__main__":
    main()
