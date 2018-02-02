#!/usr/bin/env bash

set -euox pipefail

readonly KUBECTL="kubectl ${KUBECTL_ARGS:-}"

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly DB_PASS=${DB_PASS:-root}
readonly MINIKUBE_IP=${MINIKUBE_IP:-$(minikube ip)}
readonly SERVERNAME=${SERVERNAME:-ota.ce}
readonly DNS_NAME=${DNS_NAME:-ota.local}
readonly API_BASE_URL=${API:-"http://${MINIKUBE_IP}"}
readonly VAULT_API=${VAULT_API:-"${API_BASE_URL}/v1"}
readonly OTA_API=${OTA_API:-"${API_BASE_URL}/api"}
readonly SERVER_DIR="${SCRIPT_DIR}/../${SERVERNAME}"


try_command() {
  local name=$1
  local output=$2
  local command=${@:3}
  local n=0
  local max=100
  while true; do
    if [[ ${output} = true ]]; then
      eval "$command" && return 0
    else
      eval "$command" 1>/dev/null 2>&1 && return 0
    fi
    [[ $((n++)) -gt $max ]] && return 1
    echo >&2 "Waiting for $name"
    sleep 5s
  done
}

print_pod_name() {
  app_name=${1}
  ${KUBECTL} get pods -l app=${app_name} -o json -o=jsonpath='{.items[0].metadata.name}'
}

print_hosts() {
  try_command ingress false "${KUBECTL} get ingress -o json \
    | jq --exit-status '.items[0].status.loadBalancer.ingress'"
  ${KUBECTL} get ingress --no-headers | awk '{print $3 " " $2}'
}

wait_for_service() {
  service_name=${1}
  try_command "${service_name}" false "[ -n \"\$(${KUBECTL} get deploy ${service_name} -o json \
    | jq '.status.conditions[]? | select(.type == \"Available\" and .status == \"True\")')\" ]"
  print_pod_name "${service_name}"
}

wait_for_containers() {
  try_command "containers" false "[ -n \$(${KUBECTL} get pods -o jsonpath \
    --template='{.items[*].status.containerStatuses[?(@.ready!=true)].name}')]"
}

create_databases() {
  mysql_name=$(wait_for_service "mysql")
  ${KUBECTL} cp "${SCRIPT_DIR}/create_databases.sql" "${mysql_name}:/tmp/create_databases.sql"
  ${KUBECTL} exec -ti "${mysql_name}" -- bash -c "mysql -p${DB_PASS} < /tmp/create_databases.sql"
}

unseal_vault() {
  wait_for_containers
  wait_for_service "tuf-vault"
  local host="Host: tuf-vault.${DNS_NAME}"

  try_command "vault" false "http --check-status --ignore-stdin ${VAULT_API}/sys/init \"${host}\""
  local status=$(http --ignore-stdin "${VAULT_API}/sys/health" "${host}")

  if [ "$(echo ${status} | jq --raw-output '.initialized')" = "false" ]; then
    local result=$(http --check-status --ignore-stdin PUT "${VAULT_API}/sys/init" "${host}" \
      secret_shares:=1 secret_threshold:=1)
    local key=$(echo $result | jq --raw-output '.keys[0]')
    local token=$(echo $result | jq --raw-output '.root_token')
    ${KUBECTL} create secret generic vault-init --from-literal=token=${token} --from-literal=key=${key}
  else
    local key=$(${KUBECTL} get secret vault-init -o jsonpath --template='{.data.key}' | base64 --decode)
    local token=$(${KUBECTL} get secret vault-init -o jsonpath --template='{.data.token}' | base64 --decode)
  fi

  http --ignore-stdin --check-status PUT "${VAULT_API}/sys/unseal" "${host}" key=${key}
  http --ignore-stdin PUT "${VAULT_API}/sys/mounts/ota-tuf/keys" "${host}" "X-Vault-Token: ${token}" type=generic
  http --ignore-stdin --check-status PUT "${VAULT_API}/sys/policy/tuf" "${host}" "X-Vault-Token: ${token}" rules=@${SCRIPT_DIR}/tuf-policy.hcl
  http --ignore-stdin --check-status PUT "${VAULT_API}/auth/token/create" "${host}" "X-Vault-Token: ${token}" id=${KEYSERVER_TOKEN} policies:='["tuf"]' period="72h"
}

start_services() {
  if [ -e ${SERVER_DIR}/credentials.zip ]
  then
    return 0
  fi

  wait_for_containers
  local ns="x-ats-namespace: default"
  local ks="Host: tuf-keyserver.${DNS_NAME}"
  local repo="Host: tuf-reposerver.${DNS_NAME}"
  local dir="Host: director.${DNS_NAME}"

  local id=$(http --ignore-stdin --check-status --print=b \
    POST ${OTA_API}/v1/user_repo "${repo}" "${ns}" | jq --raw-output .)
  http --ignore-stdin --check-status post ${OTA_API}/v1/admin/repo "${dir}" "${ns}"
  try_command "keys" false "http --ignore-stdin --check-status ${OTA_API}/v1/root/${id} \"${ks}\""
  local keys=$(http --ignore-stdin --check-status ${OTA_API}/v1/root/${id}/keys/targets/pairs "${ks}")
  echo ${keys} | jq -r 'del(.[0].keyval.private)' | jq -r '.[0]' > ${SERVER_DIR}/targets.pub
  echo ${keys} | jq -r 'del(.[0].keyval.public)'  | jq -r '.[0]' > ${SERVER_DIR}/targets.sec
  try_command "download root.json" true \
    "http --ignore-stdin --check-status -d -o \"${SERVER_DIR}/root.json\" \
    ${OTA_API}/v1/user_repo/root.json \"${repo}\" \"${ns}\""
  echo "http://tuf-reposerver.${DNS_NAME}" > ${SERVER_DIR}/tufrepo.url
  echo "https://${SERVERNAME}:30443" > ${SERVER_DIR}/autoprov.url
  cat > ${SERVER_DIR}/treehub.json <<EOF
{
    "no_auth": true,
    "ostree": {
        "server": "http://treehub.${DNS_NAME}/api/v3/"
    }
}
EOF
  zip --quiet --junk-paths ${SERVER_DIR}/{credentials.zip,autoprov.url,server_ca.pem,tufrepo.url,targets.pub,targets.sec,treehub.json,root.json}
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
  "start_services")
    start_services
    ;;
  "print_hosts")
    print_hosts
    ;;
  "wait_for_containers")
    wait_for_containers
    ;;
  *)
    echo "Unknown command: ${command}"
    exit 1
    ;;
esac
