#!/usr/bin/env bash
# Prepares a freshly created environment for the demo:
#   1. applies each service's db/init.sql on its RDS database
#   2. registers the internal service API key hash in auth-service's DB
#   3. creates a demo flag + targeting rule
#
# Runs psql inside short-lived pods (RDS is only reachable from the VPC) using
# the Secrets that External Secrets Operator already created in the cluster.
# Expects the service repos checked out next to the gitops repo.
set -euo pipefail

NS=togglemaster
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
REGION="${AWS_REGION:-us-east-2}"

psql_pod() { # <service>  (SQL on stdin)
  local svc=$1
  kubectl -n "$NS" run "psql-${svc}-$RANDOM" --rm -i --restart=Never --quiet \
    --image=postgres:16-alpine \
    --overrides="{\"spec\":{\"containers\":[{\"name\":\"psql\",\"image\":\"postgres:16-alpine\",\"stdin\":true,\"stdinOnce\":true,\"command\":[\"sh\",\"-c\",\"psql \\\"\$DATABASE_URL\\\" -v ON_ERROR_STOP=1 -f -\"],\"envFrom\":[{\"secretRef\":{\"name\":\"${svc}-secrets\"}}]}]}}"
}

for svc in auth-service flag-service targeting-service; do
  echo ">> ${svc}: init.sql"
  psql_pod "$svc" < "$ROOT/$svc/db/init.sql"
done

echo ">> auth-service: registrando a chave interna (evaluation -> flag/targeting)"
KEY=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id togglemaster-service-api-key --query SecretString --output text)
HASH=$(printf '%s' "$KEY" | sha256sum | cut -d' ' -f1)
printf "INSERT INTO api_keys (name, key_hash) VALUES ('evaluation-service', '%s') ON CONFLICT (key_hash) DO NOTHING;\n" "$HASH" \
  | psql_pod auth-service

echo ">> flag/targeting: flag de demo 'enable-new-checkout' (50%% dos usuários)"
printf "INSERT INTO flags (name, description, is_enabled) VALUES ('enable-new-checkout', 'Demo Fase 4', true) ON CONFLICT (name) DO NOTHING;\n" \
  | psql_pod flag-service
printf "INSERT INTO targeting_rules (flag_name, is_enabled, rules) VALUES ('enable-new-checkout', true, '{\"type\": \"PERCENTAGE\", \"value\": 50}') ON CONFLICT (flag_name) DO NOTHING;\n" \
  | psql_pod targeting-service

echo "OK"
