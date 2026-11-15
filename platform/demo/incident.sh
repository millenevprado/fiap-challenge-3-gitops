#!/usr/bin/env bash
# "A Prova Real": injects a failure in auth-service.
#
# Turns on the in-memory fault in EVERY auth-service pod (POST /admin/fault):
# /validate starts answering HTTP 500 -> flag/targeting-service reject requests
# -> 5xx rate of auth-service > 5% -> Grafana alert fires -> PagerDuty incident
# + Slack message. The fault lives only in memory, so restarting the pods
# (the runbook action) really fixes it.
#
#   ./incident.sh          inject the fault
#   ./incident.sh status   show the fault state of each pod
#   ./incident.sh fix      runbook action: kubectl rollout restart
set -euo pipefail
NS=togglemaster

case "${1:-on}" in
  on) WGET_OPTS="--post-data=" ;;
  status) WGET_OPTS="" ;;
  fix)
    kubectl -n "$NS" rollout restart deployment/auth-service
    kubectl -n "$NS" rollout status deployment/auth-service --timeout=180s
    exit 0
    ;;
  *) echo "uso: $0 [on|status|fix]"; exit 1 ;;
esac

for pod in $(kubectl -n "$NS" get pods -l app.kubernetes.io/name=auth-service -o name); do
  printf '%s: ' "$pod"
  kubectl -n "$NS" exec "$pod" -- sh -c \
    "wget -q -O - $WGET_OPTS --header \"Authorization: Bearer \$MASTER_KEY\" http://localhost:8001/admin/fault"
  echo
done
