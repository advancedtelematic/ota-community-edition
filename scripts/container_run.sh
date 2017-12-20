#!/bin/bash

set -euo pipefail


SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DB_NAME=${DB_NAME:-mariadb}
DB_PASS=${DB_PASS:-root}
VAULT_NAME=${VAULT_NAME:-k8s_tuf-vault}
KEYSERVER_NAME=${KEYSERVER_NAME:-k8s_tuf-keyserver_tuf}
KEYSERVER_TOKEN=${KEYSERVER_TOKEN:-/keyserver-token}


print_container_id() {
  container_name=${1}
  docker ps -qf "name=${container_name}"
}

wait_for_container() {
  container_name=${1}
  wait_after_ready=${2:-0}
  until [[ $(print_container_id "${container_name}") ]]; do
    echo >&2 "waiting for ${container_name}..."
    sleep 10;
  done
  sleep "${wait_after_ready}"
  print_container_id "${container_name}"
}

create_databases() {
  container_id=$(wait_for_container "${DB_NAME}" 15)
  docker cp "${SCRIPT_DIR}/create_databases.sql" "${container_id}:/tmp"
  docker exec -it "${container_id}" bash -c "mysql -p${DB_PASS} < /tmp/create_databases.sql"
}

unseal_vault() {
  container_id=$(wait_for_container "${VAULT_NAME}" 5)
  docker cp "${SCRIPT_DIR}/unseal_vault.sh" "${container_id}:/tmp"
  docker exec "${container_id}" "/tmp/unseal_vault.sh"
}

copy_tokens() {
  vault_id=$(wait_for_container "${VAULT_NAME}")
  keyserver_id=$(wait_for_container "${KEYSERVER_NAME}")
  temp_file=$(mktemp)
  docker cp "${vault_id}:${KEYSERVER_TOKEN}" "${temp_file}"
  docker cp "${temp_file}" "${keyserver_id}:${KEYSERVER_TOKEN}"
  rm "${temp_file}"
}


[ $# -lt 1 ] && { echo "Usage: $0 <command>"; exit 1; }
command=$(echo "$1" | sed 's/-/_/g')

eval $(minikube docker-env)
case "${command}" in
  "create_databases")
    create_databases
    ;;
  "unseal_vault")
    unseal_vault
    ;;
  "copy_tokens")
    copy_tokens
    ;;
  *)
    echo "Unknown command: ${command}"
    exit 1
    ;;
esac
