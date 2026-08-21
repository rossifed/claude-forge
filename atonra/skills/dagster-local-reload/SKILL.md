---
name: dagster-local-reload
description: "Repoint and reload the local Dagster code location (the data-pipeline container) so code/dbt changes take effect. Use when local Dagster (localhost:3000) does not reflect your changes, when working across two parallel repo checkouts (e.g. fundy vs fundy_main) and the container mounts the wrong one, when a new dbt model/asset does not appear, or when the code location fails to load. Covers: which checkout is live, force-recreate to repoint, in-container dbt parse + restart, and verifying the load via GraphQL (not docker logs)."
user-invocable: true
---

# Local Dagster — reload & repoint

The local Dagster stack (webserver `localhost:3000` + code location `data-pipeline` on `:4000`) runs from
**exactly ONE repo checkout at a time**. The `data-pipeline` container **bind-mounts that checkout's
`src/data`** (`data` ro, `dbt_project` rw, `sling` ro). There is a single container (fixed
`container_name`), so the **several parallel checkouts** on this machine (seen in the wild:
`~/dev/atonra/fundy`, `~/dev/atonra/fundy_main/fundy`, `~/dev/atonra/estimates/fundy` — assume there are
MORE than two) **cannot all have a live Dagster** — whichever you last recreated the container from wins.
Editing files in a different checkout changes nothing.

**ALWAYS start at step 2 (recreate from YOUR checkout) — do not trust any prior belief about which checkout
is mounted** (a memory note, a "it was fundy_main last time", an earlier `docker inspect`). Another session
or task may have recreated the container from a different checkout since. The recreate is cheap and
idempotent; verifying the mount (step 3) before you believe it is mandatory. Chasing a symptom (a missing
asset, an "OOM") while the container silently mounts the wrong checkout wastes the most time of all.

Three facts that cause most of the lost time:
- **gRPC does NOT hot-reload.** A change is picked up only after the container restarts/recreates.
- **Container `healthy` ≠ definitions loaded.** Healthy only means the gRPC port opened. A single unresolved
  asset job (e.g. a stale manifest missing a model added on `main`) crashes the WHOLE code location.
- **`RestartPolicy=always` + a failing load = a crash-LOOP that KILLS your `docker exec`.** When the code
  server can't load definitions it exits, the policy restarts it instantly, and that restart tears down any
  in-flight `docker exec` (e.g. your `dbt parse`) — which dies with **exit 137, looking exactly like an OOM
  but is NOT one** (`docker inspect --format '{{.State.OOMKilled}}'` = false, `RestartCount` climbing). See
  step 4's crash-loop path.

## Procedure — make THIS checkout live and reload (run in order, check each "Expect")

**1. From the repo root of the checkout you are editing, load its env:**
```bash
set -a; source .env.secrets; set +a
```

**2. Recreate the container from HERE (repoints the mount to this checkout):**
```bash
docker compose -f infrastructure/docker-compose/docker-compose.yml \
  --profile dagster-local up -d --force-recreate --no-build data-pipeline
```
Expect: `Container data-pipeline  Started`. (Same compose project name across checkouts → this recreates the
SAME container pointing here; no orphan. Service is defined in `services/code-locations.yml`, mount is
relative — no override needed.)

**3. Confirm the mount now points to THIS checkout:**
```bash
docker inspect data-pipeline --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' | grep src/data
```
Expect: paths under the checkout you are in. If they show the other checkout → you ran compose from the
wrong dir; redo step 1 from the right root.

**4. ONLY if you changed dbt models / the asset graph (`ref`, `source`, `deps`, `asset_key`, a new model)
— regenerate the manifest IN the container, then restart:**
```bash
docker exec -w /opt/dagster/app/dbt_project data-pipeline /opt/dagster/app/.venv/bin/dbt parse
docker restart data-pipeline
```
(Python-only change: skip `dbt parse` — step 2 already restarted. No change yet: skip step 4 entirely.
Column-only dbt edits — a changed SELECT list, no new `ref`/`source`/`asset_key` — need NEITHER `dbt parse`
NOR a manifest regen; the container reads the `.sql` fresh each run. A **Python** change (e.g. a SQLAlchemy
model) DOES need a `docker restart` so the code server re-imports it.)

**4-bis. Crash-loop path — when the `docker exec dbt parse` above keeps dying with exit 137 (NOT an OOM):**
This happens when the manifest is stale AND the Python already references the new node (e.g. a new
`dbt_op_<name>` op whose tag no node carries yet): the code server crash-loops (`RestartPolicy=always`) and
every restart kills your in-container `dbt parse`. You cannot fix it with `docker exec` because the thing you
must fix is what's causing the loop. Break the loop by regenerating the manifest in a **one-off container**
(same image + env + mount, NOT attached to the crash-looping one), then start the real container fresh:
```bash
# 0. confirm it's a crash-loop, not an OOM:
docker inspect data-pipeline --format 'OOMKilled={{.State.OOMKilled}} Restarts={{.RestartCount}}'  # OOMKilled=false, Restarts climbing
# 1. stop the loop (explicit stop overrides restart=always):
docker stop data-pipeline
# 2. replicate the container's env to an env-file (profiles.yml uses env_var() -> parse needs them):
ENVF=$(mktemp); docker inspect data-pipeline --format '{{range .Config.Env}}{{println .}}{{end}}' > "$ENVF"
# 3. regenerate the manifest in a one-off, writing target/ to the host mount (point -v at YOUR checkout):
docker run --rm --env-file "$ENVF" \
  -v "$PWD/src/data/dbt_project:/opt/dagster/app/dbt_project" -w /opt/dagster/app/dbt_project \
  fundy/data-pipeline /opt/dagster/app/.venv/bin/dbt parse
rm -f "$ENVF"
# 4. start the real container — it now loads the fresh manifest and stops looping:
docker start data-pipeline
```
(`dbt parse` does NOT connect to the DB, so the one-off needs no network. If you must `dbt compile`/`run` in a
one-off, add `--network container:data-pipeline` for DB reachability — and note the `kubectl` tunnel FLAPS,
so a lone "connection refused" is usually the tunnel reconnecting, not your model.)

**5. Wait, then verify the code location loaded WITHOUT error — via GraphQL, NOT logs:**
```bash
sleep 18
curl -s http://localhost:3000/graphql -H 'Content-Type: application/json' \
 -d '{"query":"{ workspaceOrError { ... on Workspace { locationEntries { name loadStatus locationOrLoadError { __typename ... on PythonError { message } } } } } }"}' \
 | python3 -c "
import sys, json
for e in json.load(sys.stdin)['data']['workspaceOrError']['locationEntries']:
    lo = e.get('locationOrLoadError') or {}
    print(e['name'], e['loadStatus'], 'OK' if lo.get('__typename') != 'PythonError' else 'ERROR: ' + lo.get('message','')[:200])
"
```
Expect the `data` line: `data LOADED OK`. If it shows `ERROR: …`, that message IS the real error — apply the
mapping below. **Never diagnose from `docker logs`**: it keeps old crash-loop errors, and a naive `--since`
lies (host TZ vs container UTC). If you must read logs, read only after the LAST `Started Dagster code server`.

**6. (Only if a job later fails to reach the DB) confirm DB reachability from the container:**
```bash
docker exec data-pipeline /opt/dagster/app/.venv/bin/python -c "import socket; socket.create_connection(('172.19.0.1',5435),5); print('TCP OK')"
```
Expect `TCP OK`. Else the tunnel is down or bound to `127.0.0.1`: `kubectl port-forward --address 0.0.0.0 -n factset-prd svc/cluster-factset-rw 5435:5432 &`.

## `ERROR:` at step 5 → exact fix

| Message contains | Cause | Fix |
|---|---|---|
| `Failed to resolve asset job …` / an asset key "not supplied" | stale manifest missing a model (often one added on `main`) | rerun step 4 (in-container `dbt parse` + restart). If the `dbt parse` itself dies with exit 137 → step 4-bis |
| `Invalid selected keys … int_<x>` / "non-executable" | a NEW dbt op is not exported | add `from .definitions import dbt_<name> as dbt_<name>` in `data/etl/master/assets/dbt/__init__.py`, then step 4 |
| `docker exec … dbt parse` exits **137** (not a `PythonError` in GraphQL — the exec just dies), `OOMKilled=false`, `RestartCount` climbing | crash-loop (stale manifest + new node referenced in Python) tearing down your exec — **NOT an OOM** | step 4-bis (stop → one-off `dbt parse` → start) |

**New dbt model/seed checklist** (every node needs exactly one `dbt_op_<name>` tag or it is orphaned and
never becomes an asset): tag it in `dbt_project.yml`; if it needs a NEW op, also declare it in
`data/etl/master/assets/dbt/definitions.py` AND export it in `data/etl/master/assets/dbt/__init__.py`.

## Deeper infra (DB tunnel, full alembic rebuild, env-var reload, connectivity tests)

See `src/data/docs/factset-migration/RUNBOOK-local-dev.md` (§0 covers the two-checkout case; §1–5 the rest).
