#!/bin/bash

set -euo pipefail


SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DB_NAME=${DB_NAME:-mariadb}
DB_PASS=${DB_PASS:-root}
MINIKUBE_IP=${MINIKUBE_IP:-$(minikube ip)}
VAULT_NAME=${VAULT_NAME:-tuf-vault}

print_pod_name() {
  app_name=${1}
  kubectl get po -l app=${app_name} -o json -o=jsonpath='{.items[0].metadata.name}'
}

wait_for_pod() {
  pod_name=${1}
  wait_after_ready=${2:-0}
  until [[ $(print_pod_name "${pod_name}") ]]; do
    echo >&2 "waiting for ${pod_name}..."
    sleep 10;
  done
  sleep "${wait_after_ready}"
  print_pod_name "${pod_name}"
}

retryCheck() {
    local n=0
    local try=60
    local cmd="${@: 2}"
    until eval $cmd
    do
        if [[ $((n++)) -ge $try ]]; then
            return 1
        fi
        echo "Waiting for $1" >&2
        sleep 5s
    done
    echo "$1 is ready" && return 0
}

create_databases() {
  retryCheck "mysql" "[ -n \"\$(kubectl get deploy mysql -o json | jq '.status.conditions[]? | select(.type == \"Available\" and .status == \"True\")')\" ]"
  mysql_name=$(print_pod_name mysql)
  kubectl cp "${SCRIPT_DIR}/create_databases.sql" ${mysql_name}:/tmp/create_databases.sql
  kubectl exec -ti ${mysql_name} -- bash -c "mysql -p${DB_PASS} < /tmp/create_databases.sql"
}

unseal_vault() {
  retryCheck "tuf-vault" "[ -n \"\$(kubectl get deploy tuf-vault -o json | jq '.status.conditions[]? | select(.type == \"Available\" and .status == \"True\")')\" ]"
  vault_name=$(print_pod_name "${VAULT_NAME}")
  retryCheck "vault" "http --check-status --print= --ignore-stdin http://${MINIKUBE_IP}/v1/sys/init \"Host: tuf-vault.ota.local\""
  kubectl cp ${SCRIPT_DIR}/unseal_vault.sh ${vault_name}:/tmp/unseal_vault.sh
  kubectl exec ${vault_name} /tmp/unseal_vault.sh
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
