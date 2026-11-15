#!/usr/bin/env bash
# Steady synthetic traffic for the dashboard, traces and the alert.
# Runs *inside* the cluster (pod "loadgen") with the internal service API key:
#   - GET evaluation-service /evaluate  -> full distributed trace
#     (evaluation -> flag/targeting -> auth, + SQS -> analytics)
#   - GET flag-service /flags/<name>    -> every call validates the key in
#     auth-service, so auth has constant traffic for the 5xx-rate alert.
#
#   ./load.sh        start (or restart) the generator
#   ./load.sh stop   remove it
set -euo pipefail
NS=togglemaster

kubectl -n "$NS" delete pod loadgen --ignore-not-found --wait=true >/dev/null
[ "${1:-}" = "stop" ] && { echo "loadgen removido"; exit 0; }

kubectl -n "$NS" run loadgen --restart=Never --image=curlimages/curl:8.10.1 \
  --overrides='{"spec":{"containers":[{"name":"loadgen","image":"curlimages/curl:8.10.1","envFrom":[{"secretRef":{"name":"evaluation-service-secrets"}}],"command":["sh","-c","i=0; while true; do i=$((i+1)); curl -s -o /dev/null -w \"evaluate %{http_code}\\n\" \"http://evaluation-service:8004/evaluate?user_id=user-$((i % 500))&flag_name=enable-new-checkout\"; curl -s -o /dev/null -w \"flags %{http_code}\\n\" -H \"Authorization: Bearer $SERVICE_API_KEY\" http://flag-service:8002/flags/enable-new-checkout; sleep 0.2; done"]}]}}' >/dev/null
echo "loadgen rodando. Logs: kubectl -n $NS logs -f loadgen"
