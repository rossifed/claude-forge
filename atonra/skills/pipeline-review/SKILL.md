---
name: pipeline-review
description: "Review a data-pipeline change (Dagster assets, dbt models, Sling/dlt ingestion, master loaders, serving views, data API) as a reviewer. Checks naming, assetkey/group, dbt _full/_changes parity, DAG deps, id/fk stability, golden-master index/fk integrity, SOLID/DRY/KISS, no French, tests. Outputs a verdict + ranked findings + prod-readiness call."
user-invocable: true
argument-hint: "[target: PR# | branch | commit-range | (default: current branch)]"
---

# Pipeline Review

Review a data-pipeline change against Atonra conventions and golden-source doctrine, then call prod-readiness.

**NON-NEGOTIABLE — this is a review, NOT a fix.** Produce a report and stop. NEVER edit code, NEVER create/edit a migration, NEVER commit, NEVER propose an `AskUserQuestion` that offers to start fixing. The findings are the deliverable; the author decides what to do with them. Even when a fix looks trivial and obviously correct (a missing index, a wrong comment), you describe it — you do not apply it. If the user later wants a fix, that is a separate, explicit request in its own turn.

The conventions are authoritative in the loaded context files — do NOT restate them from memory, verify against them: `dagster-patterns.md` (pipeline layers, dual-load, `_full`/`_changes` parity), `master-schema.md` (domain map, hypertables), `data-access-conventions.md` (read-vs-produce, master vs serving), `python-conventions.md`, `database-topology.md` (which MCP server is which). Docs are context to challenge, not law — verify against code and DB.

## Step 1 — Isolate the real scope

Branches here are often far behind `main` and carry unrelated work, so `git diff main..branch` is useless.

1. `git log --oneline main..<branch>` — find the contiguous run of commits that IS this feature (usually the top N, one scope prefix).
2. Confirm contiguity: `git log --format='%h %p %s' <base>..<head>` (each parent chains to the next).
3. Scope every later `git diff`/`--stat` to `<base>..<head>` and the feature's path globs. If a PR#: `gh pr view <n>`, `gh pr diff <n>`.

## Step 2 — Read in layers (source → consumer)

Follow the flow; a defect in one layer usually shows as a contradiction with the next.

| Layer | Files | Look for |
|---|---|---|
| Schema | `src/data/data/db/models/*.py`, `src/data/alembic/versions/*` | PK/index/FK, id stability, migration chain consistent with siblings |
| Staging | `dbt_project/models/staging/stg_fds_*.sql`, `sources.yml` | source-only, provider ids confined here, per-item scaling via metadata JOIN |
| Intermediate | `dbt_project/models/intermediate/int_*.sql` | id resolution (`entity_mapping`/`instrument_mapping`, `data_source_id`), one feeder per master target, `_full`/`_changes` identical logic |
| Master load | `etl/master/assets/loading/*.py`, `jobs/etl/*.py`, `schedules/*` | loader mode (Merge/CDC/CtasSwap), assetkey/group, deps, schedule wiring, confirm-token for expensive full loads |
| Serving | `dbt_project/models/serving/*.sql` | FK-bearing twin, no provider id leaked, view rebuilt after any CASCADE-dropping swap |
| API | `data/api/routes/**`, `services/**`, `schemas/**`, `main.py`, `dependencies.py` | parameterized SQL, router mounted, contract matches the physical read path |
| Tests | `tests/unit/api/`, `tests/unit/services/`, `dbt` schema.yml | parity with the established test pattern; dbt tests on small feeders |

## Step 3 — Convention checklist

Run every item; each is a potential finding.

- **Naming / source-agnostic** — FactSet only in `stg_fds_*`; master/intermediate/serving provider-neutral. Explicit names (`company_currency`, not `cmp_ccy`).
- **AssetKey & group** — namespaced `staging.fds.<domain>` → `intermediate.<domain>` → `master.<domain>` → `serving.<domain>`; group set on every asset; keys match `sources.yml` `dagster.asset_key`.
- **dbt `_full`/`_changes` parity** — if both exist, identical transformation logic (only CDC metadata + `cdc_deduplicate` may differ). A `_full`-only table must NOT reference a nonexistent `_changes` in comments (copy-paste smell).
- **DAG coherence** — deps declared for every mapping/catalog the resolution reads; a CtasSwap/rename-swap CASCADE-drops dependent views → they must be rebuilt in the SAME run; concurrency key shared between CDC and full jobs writing the same table.
- **ID & FK stability (golden master)** — natural/surrogate keys stable across reloads; a resolved fact's resolved key never flips to nullable; provider ids kept out of the golden fact (isolated in an `_unresolved`/mapping table only when it is the sole handle, justified).
- **Index & FK for a golden source** — verify the loader actually reconstitutes PK/FK/index after a full rebuild (`CtasSwapConfig.from_model` → PK as unique index, FK re-added, NOT NULL set). FK-free fact tables (market_data doctrine) are OK **only** if integrity is guaranteed by pipeline inner joins AND the serving twin carries the FKs.
- **Read-path vs contract** — for every API filter/scope the route advertises, confirm an index supports it on the target table. An endpoint that permits a scope with no supporting index on a large fact is a scalability cliff (seqscan). Flag it.
- **SOLID / DRY / KISS** — shared dimensions reached via one extension point (not duplicated per consumer); one loader per target; per-layer perimeters; no clever constructs where an explicit one reads better.
- **Security** — no string-concatenated SQL (bound params; any interpolated token must be a hard-coded literal, never user input); no secret hardcoding; unscoped-scan endpoints refused.
- **No French** — comments, docstrings, docs, commits all in English. `git diff <base>..<head> -- <feature globs> | grep -iE '\b(le|la|les|des|une|pour|avec|dans|est|cette|aussi|donc|schéma|données|chantier)\b'` on added (`^+`) lines.
- **Tests** — new routes/services have unit tests matching the repo pattern; non-trivial logic (dynamic WHERE, window aggregates, guards, union semantics) covered.

## Step 4 — Verify against the DB (cheap checks only)

Use the MCP server for the cluster the change targets (`database-topology.md` says which). Read-only. Confirm, don't assume: indexes actually present (`pg_indexes`), a field's semantics/scale before trusting a name→name mapping (`ref_v2_ref_metadata_fields`), hypertable shape (`timescaledb_information.hypertables`). Do not run heavy scans on prod; bound anything volumetric.

## Step 5 — Report

Present in chat (a review is a diagnostic, not a project artifact — do not save unless asked):

1. **Verdict headline** — ready / not-ready + the one-line reason.
2. **Strengths** — what to keep, so the author knows what not to touch.
3. **Findings, ranked** — 🔴 blocker / 🟠 major / 🟡 minor / ⚪ nit. Each: the defect, the concrete failure it causes (inputs → wrong output/scan/break), the file:line, the fix direction. Grade evidence: separate confirmed-in-code from suspected.
4. **Prod-readiness** — what must change before merge vs what can follow. State it plainly.

Then STOP. Do not edit, do not commit, do not offer to start fixing — the report is the whole deliverable (see the NON-NEGOTIABLE at the top). Wait for the author to ask, as a separate request, if they want any change made.
