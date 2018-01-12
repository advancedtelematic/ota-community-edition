#!/bin/bash

set -euo pipefail


SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DB_NAME=${DB_NAME:-mariadb}
DB_PASS=${DB_PASS:-root}
MINIKUBE_IP=${MINIKUBE_IP:-$(minikube ip)}
VAULT_NAME=${VAULT_NAME:-tuf-vault}

print_pod_name() {
  app_name=${1}
  kubectl get pods -l app=${app_name} -o json -o=jsonpath='{.items[0].metadata.name}'
}

retry_check() {
  local n=0
  local try=60
  local cmd="[ -n \"\$(${@: 2})\" ]"
  until eval $cmd 2>/dev/null; do
    [[ $((n++)) -ge $try ]] && return 1
    echo >&2 "Waiting for $1"
    sleep 5s
  done
  echo >&2 "$1 is ready"
}

wait_for_service() {
  service_name=${1}
  cmd="kubectl get deploy ${service_name} -o json \
    | jq '.status.conditions[]? | select(.type == \"Available\" and .status == \"True\")'"
  retry_check "${service_name}" ${cmd}
  print_pod_name "${service_name}"
}

create_databases() {
  mysql_name=$(wait_for_service "mysql")
  kubectl cp "${SCRIPT_DIR}/create_databases.sql" "${mysql_name}:/tmp/create_databases.sql"
  kubectl exec -ti "${mysql_name}" -- bash -c "mysql -p${DB_PASS} < /tmp/create_databases.sql"
}

unseal_vault() {
  vault_name=$(wait_for_service "tuf-vault")
  retry_check "vault" "http --check-status --print= --ignore-stdin http://${MINIKUBE_IP}/v1/sys/init 'Host: tuf-vault.ota.local'"
  kubectl cp "${SCRIPT_DIR}/unseal_vault.sh" "${vault_name}:/tmp/unseal_vault.sh"
  kubectl exec "${vault_name}" /tmp/unseal_vault.sh
}

[ $# -lt 1 ] && { echo "Usage: $0 <command>"; exit 1; }
command=$(echo "$1" | sed 's/-/_/g')

case "${command}" in
  "create_databases")
    create_databases
    ;;
  "unseal_vault")
    unseal_vault
    ;;
  *)
    echo "Unknown command: ${command}"
    exit 1
    ;;
esac
