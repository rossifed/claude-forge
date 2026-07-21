#!/usr/bin/env bash
# Keeps the kubectl port-forwards to the AWS databases alive.
#
# Each forward runs in its own retry loop: when it dies (pod restart, idle
# timeout, expired AWS SSO), it is relaunched every RETRY_DELAY_SECONDS.
# If the local port is already taken (e.g. Freelens or another session holds
# it), the loop waits in standby and takes over as soon as the port frees up.
#
# Recommended install: systemd user service `db-port-forwards` with linger
# (see claude-forge/atonra/context/remote-recovery-runbook.md).
#
# When AWS SSO expires, refresh it from anywhere (URL + code on your phone):
#   aws sso login --profile production-eks-admin --use-device-code --no-browser
# The forwards below then reconnect on their own — nothing else to do.

set -u

RETRY_DELAY_SECONDS=5

# name | namespace | service | bind_address | local_port | remote_port
# factset-prod binds 0.0.0.0 so docker containers can reach it via 172.17.0.1.
FORWARDS=(
  "financial-prod|timescaledb-prd|svc/cluster-timescaledb-rw|127.0.0.1|5434|5432"
  "factset-prod|factset-prd|svc/cluster-factset-rw|0.0.0.0|5435|5432"
  "financial-factset-prod|timescaledb-prd|svc/cluster-timescaledb-factset-rw|127.0.0.1|5436|5432"
)

port_is_taken() {
  local port="$1"
  ss -tln | awk '{print $4}' | grep -q ":${port}$"
}

keep_port_forward_alive() {
  local name="$1" namespace="$2" service="$3" bind_address="$4" local_port="$5" remote_port="$6"
  while true; do
    if port_is_taken "$local_port"; then
      sleep "$RETRY_DELAY_SECONDS"
      continue
    fi
    echo "[$(date '+%F %T')] [${name}] starting port-forward ${local_port} -> ${namespace}/${service}:${remote_port}"
    kubectl port-forward --address "$bind_address" -n "$namespace" "$service" "${local_port}:${remote_port}"
    echo "[$(date '+%F %T')] [${name}] down (SSO expired? pod restarted?) — retry in ${RETRY_DELAY_SECONDS}s"
    sleep "$RETRY_DELAY_SECONDS"
  done
}

for entry in "${FORWARDS[@]}"; do
  IFS='|' read -r name namespace service bind_address local_port remote_port <<< "$entry"
  keep_port_forward_alive "$name" "$namespace" "$service" "$bind_address" "$local_port" "$remote_port" &
done

wait
