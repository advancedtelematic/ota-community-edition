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
  local cmd="${@: 2}"
  until eval $cmd 2>/dev/null; do
    [[ $((n++)) -ge $try ]] && return 1
    echo >&2 "Waiting for $1"
    sleep 5s
  done
  echo >&2 "$1 is ready"
}

wait_for_service() {
  service_name=${1}
  cmd="[ -n \"\$(kubectl get deploy ${service_name} -o json | jq '.status.conditions[]? | select(.type == \"Available\" and .status == \"True\")')\" ]"
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
  local vaultStatus=$(http --ignore-stdin http://${MINIKUBE_IP}/v1/sys/health "Host: tuf-vault.ota.local")
  if [ "$(echo ${vaultStatus} | jq --raw-output '.initialized')" = "false" ]
  then
      local initResult=$(http --check-status --ignore-stdin PUT http://${MINIKUBE_IP}/v1/sys/init 'Host: tuf-vault.ota.local' secret_shares:=1 secret_threshold:=1)
      local unsealKey=$(echo $initResult | jq --raw-output '.keys[0]')
      local rootToken=$(echo $initResult | jq --raw-output '.root_token')
      kubectl create secret generic vault-init --from-literal=rootToken=${rootToken} --from-literal=unsealKey=${unsealKey}
  else
      local unsealKey=$(kubectl get  secret vault-init -o jsonpath --template='{.data.unsealKey}'| base64 --decode)
      local rootToken=$(kubectl get  secret vault-init -o jsonpath --template='{.data.rootToken}'| base64 --decode)
  fi
  http --ignore-stdin --check-status PUT http://${MINIKUBE_IP}/v1/sys/unseal 'Host: tuf-vault.ota.local' key=${unsealKey}
  http --ignore-stdin --check-status put http://$(minikube ip)/v1/sys/policy/tuf "Host: tuf-vault.ota.local" "X-Vault-Token: ${rootToken}" policy="path \"ota-tuf/keys/*\" {\n  policy = \"write\"\n}"
  http --ignore-stdin put http://$(minikube ip)/v1/sys/mounts/ota-tuf/keys "Host: tuf-vault.ota.local" "X-Vault-Token: ${rootToken}" type=generic
  http --ignore-stdin --check-status put http://$(minikube ip)/v1/auth/token/create "Host: tuf-vault.ota.local" "X-Vault-Token: ${rootToken}" id=${KEYSERVER_TOKEN} policies:='["tuf"]' period="72h"
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
