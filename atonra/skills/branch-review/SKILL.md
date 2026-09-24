---
name: branch-review
description: "Convention & design review of the active branch of the current workspace, layer by layer — Python services, Dagster/dbt/data pipelines (raw→staging→intermediate→master→serving), DB models/migrations, frontend. Checks project conventions, SOLID/DRY/KISS/DDD, pure-vs-impure separation, regressions, data-model placement, id stability, orphan assets, dropped views, perf, tests and ruff. Ranked findings + open questions; never fixes."
user-invocable: true
argument-hint: "[override target: PR# | branch | commit-range | paths — default: active branch of the workspace repo]"
---

# Branch Review

Review the work on the active branch of the current workspace against the conventions and doctrine of the project it lives in, layer by layer, then call merge-readiness.

**Scope vs the built-in `/code-review`:** `/code-review` hunts correctness bugs (logic, security, edge cases). This skill covers what it does not: conventions, design, layer responsibilities, data-model doctrine, orchestration. Do not duplicate a generic bug hunt here — report a bug only when you hit one while checking the items below.

**NON-NEGOTIABLE — review, not fix.** Produce a report and stop. NEVER edit code, create a migration, commit, or offer to start fixing. Even a trivial fix is described, not applied. A fix is a separate, explicit request.

**NON-NEGOTIABLE — doubt = question, never initiative.** When intent, business meaning, a convention, or a perf behavior is uncertain, do NOT pick an interpretation and grade against it. Put it under **Open questions** in the report (what is unclear, why it matters, what evidence would settle it — e.g. an `EXPLAIN` to run). A finding built on a guess is worse than a question.

## Step 1 — Resolve the workspace repo and its active branch

The target is the branch checked out in the workspace the session runs in — never another checkout of the same repo elsewhere on disk.

1. From the working directory: `git rev-parse --show-toplevel`. If it fails (workspace folder wraps the repo, e.g. `fundy_main/` containing `fundy/`), list direct child repos (`find . -maxdepth 2 -name .git`). Exactly one → use it; several → ask which one.
2. Active branch: `git -C <repo> branch --show-current`. If it is the default branch (`main`/`master`) or detached HEAD → ask what to review instead of reviewing `main`.
3. Only if the user passed an argument (PR#, branch, range, paths), review that instead: PR → `gh pr view <n>`, `gh pr diff <n>`.

## Step 2 — Isolate the real scope of the branch

Branches are often behind `main` and carry unrelated work, so `git diff main..branch` is useless.

1. `git log --oneline main..<branch>` → keep the contiguous run of commits that IS this feature (one scope prefix). Confirm contiguity with `git log --format='%h %p %s' <base>..<head>`. If the feature boundary is unclear → ask.
2. Add the uncommitted work of the workspace (`git status`, `git diff`, `git diff --staged`) — it is part of the branch's work.
3. Scope every later diff to `<base>..<head>` + uncommitted, and to the feature's paths. State repo, branch, commit range, and uncommitted files at the top of the report.

## Step 3 — Load the project's conventions (do not assume them)

Conventions are the project's, not generic taste. Before judging, read what applies to the touched paths:

- `AGENTS.md` / `CLAUDE.md` at repo root and in the touched service; `pyproject.toml` (`[tool.ruff]`, pyright, pytest config); `package.json`/lint config for frontend.
- 2-3 **sibling files** of each changed file (same folder, same kind: another asset, another route, another dbt model). The dominant pattern there is the convention — naming, module layout, error handling, test shape. A deviation is a finding unless the change justifies it.
- Loaded context files (`dagster-patterns.md`, `data-access-conventions.md`, `master-schema.md`, `python-conventions.md`, `react-conventions.md`, `data-knowledge.md`) are authoritative references — verify against them, do not restate from memory. Docs can be stale: when code/DB contradicts a doc, report the contradiction.

## Step 4 — Detect layers, load the matching checklist

Classify every changed file, then read ONLY the checklists for the layers present:

| Layer | Typical paths | Checklist |
|---|---|---|
| Python service / library code | `src/<service>/**/*.py` (api, services, schemas, domain) | [python.md](python.md) |
| Data pipeline & DB | Dagster assets/jobs/schedules, `dbt_project/**`, `sling/**`, `dlt_pipelines/**`, SQLAlchemy models, `alembic/versions/**`, serving views | [data.md](data.md) **and** [python.md](python.md) for its Python |
| Frontend | `*.ts`, `*.tsx`, routes, components | [frontend.md](frontend.md) |

Run every item of each loaded checklist; each is a potential finding.

## Step 5 — Cross-cutting checks (every layer)

- **Impact on the existing** — for every changed public symbol (function signature, table/column, view, asset key, API field, route): find all consumers (`grep` across the repo, dbt `ref()`, asset deps, frontend calls). A consumer not updated = regression. Removed/renamed without a two-phase path (add → migrate consumers → drop) = breaking change.
- **Long-term side effects** — behavior that is correct today but drifts: state that accumulates without cleanup, data that is never refreshed, a default that silently changes meaning, a hard-coded list that the source will outgrow.
- **Duplicated / redundant logic** — search the codebase for an existing function, macro, model, or service that already does this (same join, same transformation, same helper). Re-implementing it is a finding — name the existing one.
- **Separation of concerns** — each module/layer has one reason to change; business rules not in transport (routes), IO not in domain logic, SQL not scattered across unrelated modules.
- **Language** — all code, comments, docstrings, docs, commits in English. Check added lines: `git diff <base>..<head> | grep '^+' | grep -iE '\b(le|la|les|des|une|pour|avec|dans|est|cette|donc|données)\b'`.

## Step 6 — Run the tooling (read-only)

Run on the touched scope, from the service directory, and report the actual output — never claim "passes" without running it:

- `ruff check <paths>` and `ruff format --check <paths>`
- `pyright <paths>` when the project configures it
- `pytest <related test paths>` — and list which changed behaviors have NO test
- dbt: `dbt parse` (or `dbt compile -s <models>`) when models changed
- Frontend: the project's lint/typecheck/test scripts (`bun run lint`, `bun test`, …)

If a tool cannot run (missing env, DB, secrets), say so explicitly — "not run: <reason>" — do not skip silently.

## Step 7 — Verify against the DB (cheap, read-only)

Only when the change touches data. Use the MCP server of the cluster the change targets (`database-topology.md` + memory say which is live). Confirm, don't assume: column type/length vs actual data (`max(length())`, `max(value)`), indexes present (`pg_indexes`), dependent views (`pg_depend`/`information_schema.view_table_usage`), source field semantics/scale (`ref_v2_ref_metadata_fields`). Bound every volumetric query. `EXPLAIN` (without `ANALYZE`) is safe; any `EXPLAIN ANALYZE` or heavy scan on prod → propose it as an Open question instead of running it.

## Step 8 — Report

Present in chat (do not save to a file unless asked):

1. **Scope reviewed** — commits/paths, layers detected, checklists applied.
2. **Verdict** — ready / not ready + one-line reason.
3. **Strengths** — what to keep, so the author knows what not to touch.
4. **Findings, ranked** — 🔴 blocker / 🟠 major / 🟡 minor / ⚪ nit. Each: the defect, the concrete failure (input/state → wrong output, scan, break), `file:line`, fix direction. Mark each **confirmed** (seen in code/DB/tool output) or **suspected** (inferred).
5. **Tooling results** — ruff / pyright / pytest / dbt: pass, fail (with output), or not run (reason).
6. **Open questions** — every doubt from the review, each with why it matters and how to settle it.
7. **Merge-readiness** — must-fix before merge vs can-follow.

Then STOP. Wait for the author to answer the open questions or ask for fixes.
