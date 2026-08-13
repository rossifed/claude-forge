---
name: dagster-local-reload
description: "Repoint and reload the local Dagster code location (the data-pipeline container) so code/dbt changes take effect. Use when local Dagster (localhost:3000) does not reflect your changes, when working across two parallel repo checkouts (e.g. fundy vs fundy_main) and the container mounts the wrong one, when a new dbt model/asset does not appear, or when the code location fails to load. Covers: which checkout is live, force-recreate to repoint, in-container dbt parse + restart, and verifying the load via GraphQL (not docker logs)."
user-invocable: true
---

# Local Dagster — reload & repoint

The local Dagster stack (webserver `localhost:3000` + code location `data-pipeline` on `:4000`) runs from
**exactly ONE repo checkout at a time**. The `data-pipeline` container **bind-mounts that checkout's
`src/data`** (`data` ro, `dbt_project` rw, `sling` ro). There is a single container (fixed
`container_name`), so two parallel checkouts (e.g. `~/dev/atonra/fundy` and `~/dev/atonra/fundy_main/fundy`)
**cannot both have a live Dagster** — whichever you last recreated the container from wins. Editing files in
a different checkout changes nothing.

Two facts that cause most of the lost time:
- **gRPC does NOT hot-reload.** A change is picked up only after the container restarts/recreates.
- **Container `healthy` ≠ definitions loaded.** Healthy only means the gRPC port opened. A single unresolved
  asset job (e.g. a stale manifest missing a model added on `main`) crashes the WHOLE code location.

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
(Python-only change: skip `dbt parse` — step 2 already restarted. No change yet: skip step 4 entirely.)

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
| `Failed to resolve asset job …` / an asset key "not supplied" | stale manifest missing a model (often one added on `main`) | rerun step 4 (in-container `dbt parse` + restart) |
| `Invalid selected keys … int_<x>` / "non-executable" | a NEW dbt op is not exported | add `from .definitions import dbt_<name> as dbt_<name>` in `data/etl/master/assets/dbt/__init__.py`, then step 4 |

**New dbt model/seed checklist** (every node needs exactly one `dbt_op_<name>` tag or it is orphaned and
never becomes an asset): tag it in `dbt_project.yml`; if it needs a NEW op, also declare it in
`data/etl/master/assets/dbt/definitions.py` AND export it in `data/etl/master/assets/dbt/__init__.py`.

## Deeper infra (DB tunnel, full alembic rebuild, env-var reload, connectivity tests)

See `src/data/docs/factset-migration/RUNBOOK-local-dev.md` (§0 covers the two-checkout case; §1–5 the rest).
