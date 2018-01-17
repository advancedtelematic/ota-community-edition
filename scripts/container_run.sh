#!/bin/bash

set -euo pipefail


SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DB_PASS=${DB_PASS:-root}
MINIKUBE_IP=${MINIKUBE_IP:-$(minikube ip)}
SERVERNAME=${SERVERNAME:-ota.ce}
readonly SERVER_DIR="${SCRIPT_DIR}/../${SERVERNAME}"

print_pod_name() {
  app_name=${1}
  kubectl get pods -l app=${app_name} -o json -o=jsonpath='{.items[0].metadata.name}'
}

try_command() {
  local name=$1
  local command=${@:2}
  local n=0
  local max=100
  while true; do
    eval "$command" 1>/dev/null 2>&1 && return 0
    [[ $((n++)) -gt $max ]] && return 1
    echo >&2 "Waiting for $name"
    sleep 5s
  done
}

try_command_no_redirect() {
    local name=$1
    local command=${@:2}
    local n=0
    local max=100
    while true; do
        eval "$command" && return 0
        [[ $((n++)) -gt $max ]] && return 1
        echo >&2 "Waiting for $name"
        sleep 5s
    done
}
wait_for_service() {
  service_name=${1}
  try_command "${service_name}" "[ -n \"\$(kubectl get deploy ${service_name} -o json \
    | jq '.status.conditions[]? | select(.type == \"Available\" and .status == \"True\")')\" ]"
  print_pod_name "${service_name}"
}

wait_for_containers() {
  try_command "containers" "[ -n \$(kubectl get po -o jsonpath --template='{.items[*].status.containerStatuses[?(@.ready!=true)].name}')]"
}

create_databases() {
  mysql_name=$(wait_for_service "mysql")
  kubectl cp "${SCRIPT_DIR}/create_databases.sql" "${mysql_name}:/tmp/create_databases.sql"
  kubectl exec -ti "${mysql_name}" -- bash -c "mysql -p${DB_PASS} < /tmp/create_databases.sql"
}

unseal_vault() {
  vault_name=$(wait_for_service "tuf-vault")
  local api="http://${MINIKUBE_IP}/v1"
  local host="Host: tuf-vault.ota.local"
  try_command "vault" "http --check-status --ignore-stdin ${api}/sys/init \"${host}\""

  local status=$(http --ignore-stdin "${api}/sys/health" "${host}")
  if [ "$(echo ${status} | jq --raw-output '.initialized')" = "false" ]; then
    local result=$(http --check-status --ignore-stdin PUT "${api}/sys/init" "${host}" \
      secret_shares:=1 secret_threshold:=1)
    local key=$(echo $result | jq --raw-output '.keys[0]')
    local token=$(echo $result | jq --raw-output '.root_token')
    kubectl create secret generic vault-init --from-literal=token=${token} --from-literal=key=${key}
  else
    local key=$(kubectl get secret vault-init -o jsonpath --template='{.data.key}' | base64 --decode)
    local token=$(kubectl get secret vault-init -o jsonpath --template='{.data.token}' | base64 --decode)
  fi

  http --ignore-stdin --check-status PUT "${api}/sys/unseal" "${host}" key=${key}
  http --ignore-stdin PUT "${api}/sys/mounts/ota-tuf/keys" "${host}" "X-Vault-Token: ${token}" type=generic
  http --ignore-stdin --check-status PUT "${api}/sys/policy/tuf" "${host}" "X-Vault-Token: ${token}" rules=@${SCRIPT_DIR}/tuf-policy.hcl
  http --ignore-stdin --check-status PUT "${api}/auth/token/create" "${host}" "X-Vault-Token: ${token}" id=${KEYSERVER_TOKEN} policies:='["tuf"]' period="72h"
}

print_hosts() {
  try_command ingress "kubectl get ingress -o json \
    | jq --exit-status '.items[0].status.loadBalancer.ingress'"
  kubectl get ingress --no-headers | awk '{print $3 " " $2}'
}

init() {
  local repoId=$(http --ignore-stdin --check-status --print=b post http://$(minikube ip)/api/v1/user_repo "Host: tuf-reposerver.ota.local" "x-ats-namespace: default" | jq --raw-output .)
  http --ignore-stdin --check-status post http://$(minikube ip)/api/v1/admin/repo "Host: director.ota.local" "x-ats-namespace: default"
  try_command "keys" "http --ignore-stdin --check-status http://${MINIKUBE_IP}/api/v1/root/${repoId} \"Host: tuf-keyserver.ota.local\""
  local keys=$(http --ignore-stdin --check-status http://${MINIKUBE_IP}/api/v1/root/${repoId}/keys/targets/pairs "Host: tuf-keyserver.ota.local")
  echo ${keys} | jq -r 'del(.[0].keyval.private)' | jq -r '.[0]' > ${SERVER_DIR}/targets.pub
  echo ${keys} | jq -r 'del(.[0].keyval.public)'  | jq -r '.[0]' > ${SERVER_DIR}/targets.sec
  try_command_no_redirect "download root.json" "http --ignore-stdin --check-status -d -o \"${SERVER_DIR}/root.json\" http://${MINIKUBE_IP}/api/v1/user_repo/root.json \"Host: tuf-reposerver.ota.local\" \"x-ats-namespace: default\""
  echo "http://tuf-reposerver.ota.local" > ${SERVER_DIR}/tufrepo.url
  echo https://${SERVERNAME}:30443 > ${SERVER_DIR}/autoprov.url
  cat > ${SERVER_DIR}/treehub.json <<EOF
{
    "no_auth": true,
    "ostree": {
        "server": "http://treehub.ota.local/api/v3/"
    }
}
EOF
  zip -qj ${SERVER_DIR}/credentials.zip ${SERVER_DIR}/autoprov.url ${SERVER_DIR}/server_ca.pem \
      ${SERVER_DIR}/tufrepo.url ${SERVER_DIR}/targets.pub ${SERVER_DIR}/targets.sec ${SERVER_DIR}/treehub.json \
      ${SERVER_DIR}/root.json
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
  "print_hosts")
    print_hosts
    ;;
  "init")
    init
    ;;
  "wait_for_containers")
    wait_for_containers
    ;;
  *)
    echo "Unknown command: ${command}"
    exit 1
    ;;
esac
