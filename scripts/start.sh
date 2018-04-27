#!/bin/bash

[[ ${DEBUG} = true ]] && set -x
set -euo pipefail

readonly KUBECTL=${KUBECTL:-kubectl}
readonly CWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly DNS_NAME=${DNS_NAME:-ota.local}
export   SERVER_NAME=${SERVER_NAME:-ota.ce}
readonly SERVER_DIR=${SERVER_DIR:-${CWD}/../generated/${SERVER_NAME}}
readonly DEVICES_DIR=${DEVICES_DIR:-${SERVER_DIR}/devices}
readonly DB_PASS=${DB_PASS:-root}
readonly VAULT_SHARES=${VAULT_SHARES:-5}
readonly VAULT_THRESHOLD=${VAULT_THRESHOLD:-3}

readonly SKIP_CLIENT=${SKIP_CLIENT:-false}
readonly SKIP_IMAGES=${SKIP_IMAGES:-false}
readonly SKIP_INGRESS=${SKIP_INGRESS:-false}
readonly SKIP_WEAVE=${SKIP_WEAVE:-false}


check_dependencies() {
  for cmd in ${DEPENDENCIES:-bash curl make http jq openssl kubectl kops}; do
    [[ $(command -v "${cmd}") ]] || { echo "Please install '${cmd}'."; exit 1; }
  done
}

retry_command() {
  local name=${1}
  local command=${@:2}
  local n=0
  local max=100
  while true; do
    eval "${command}" &>/dev/null && return 0
    [[ $((n++)) -gt $max ]] && return 1
    echo >&2 "Waiting for ${name}"
    sleep 5s
  done
}

first_pod() {
  local app=${1}
  ${KUBECTL} get pods --selector=app="${app}" --output jsonpath='{.items[0].metadata.name}'
}

wait_for_pods() {
  local app=${1}
  retry_command "${app}" "[[ true = \$(${KUBECTL} get pods --selector=app=${app} --output json \
    | jq --exit-status '(.items | length > 0) and ([.items[].status.containerStatuses[].ready] | all)') ]]"
  first_pod "${app}"
}

print_hosts() {
  retry_command "ingress" "${KUBECTL} get ingress -o json \
    | jq --exit-status '.items[0].status.loadBalancer.ingress'"
  ${KUBECTL} get ingress --no-headers | awk '{print $3 " " $2}'
}

kill_pid() {
  local pid=${1}
  kill -0 "${pid}" 2>/dev/null || return 0
  kill -9 "${pid}"
}

make_template() {
  local template=$1
  local output="${CWD}/../generated/${template}"
  mkdir -p "$(dirname "${output}")"
  kops toolbox template \
    --template "${template}" \
    --values config/images.yaml \
    --values config/infra.yaml \
    --values config/secrets.yaml \
    --values config/resources.yaml \
    --output "${output}"
}

apply_template() {
  local template=$1
  make_template "${template}"
  ${KUBECTL} apply --filename "${CWD}/../generated/${template}"
}

pull_images() {
  [[ ${SKIP_IMAGES} == true ]] && return 0;

  ${KUBECTL} get configmap pull-images &>/dev/null || {
    ${KUBECTL} create configmap --from-file config/images.yaml pull-images
  }

  apply_template templates/images
  wait_for_pods pull-images
}

new_client() {
  export DEVICE_UUID=${DEVICE_UUID:-$(uuidgen | tr "[:upper:]" "[:lower:]")}
  local device_id=${DEVICE_ID:-${DEVICE_UUID}}
  local device_dir="${DEVICES_DIR}/${DEVICE_UUID}"
  mkdir -p "${device_dir}"

  openssl ecparam -genkey -name prime256v1 | openssl ec -out "${device_dir}/pkey.ec.pem"
  openssl pkcs8 -topk8 -nocrypt -in "${device_dir}/pkey.ec.pem" -out "${device_dir}/pkey.pem"
  openssl req -new -config "${CWD}/certs/client.cnf" -key "${device_dir}/pkey.pem" -out "${device_dir}/${device_id}.csr"
  openssl x509 -req -days 365 -extfile "${CWD}/certs/client.ext" -in "${device_dir}/${device_id}.csr" \
    -CAkey "${DEVICES_DIR}/ca.key" -CA "${DEVICES_DIR}/ca.crt" -CAcreateserial -out "${device_dir}/client.pem"
  cat "${device_dir}/client.pem" "${DEVICES_DIR}/ca.crt" > "${device_dir}/${device_id}.chain.pem"
  ln -s "${SERVER_DIR}/server_ca.pem" "${device_dir}/ca.pem" || true
  openssl x509 -in "${device_dir}/client.pem" -text -noout

  [[ ${SKIP_CLIENT} == true ]] && return 0

  ${KUBECTL} proxy --port 8200 &
  local pid=$!
  trap "kill_pid ${pid}" EXIT
  sleep 3s

  local addr=${DEVICE_ADDR:-localhost}
  local port=${DEVICE_PORT:-2222}
  local gateway=${GATEWAY_ADDR:-$(${KUBECTL} get nodes --output jsonpath \
    --template='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}
  local registry="http://localhost:8200/api/v1/namespaces/default/services/registry/proxy/api/v1"
  local options="-o StrictHostKeyChecking=no"

  http PUT "${registry}/devices" deviceUuid="${DEVICE_UUID}" deviceId="${device_id}" \
    deviceName="${device_id}" deviceType=Other credentials=@"${device_dir}/client.pem"
  ssh ${options} "root@${addr}" -p "${port}" "echo \"${gateway} ota.ce\" >> /etc/hosts"
  scp -P "${port}" ${options} "${device_dir}/client.pem" "root@${addr}:/var/sota/client.pem"
  scp -P "${port}" ${options} "${device_dir}/pkey.pem" "root@${addr}:/var/sota/pkey.pem"

  kill_pid "${pid}"
}

new_server() {
  ${KUBECTL} get secret gateway-tls &>/dev/null && return 0
  mkdir -p "${SERVER_DIR}" "${DEVICES_DIR}"

  openssl ecparam -genkey -name prime256v1 | openssl ec -out "${SERVER_DIR}/ca.key"
  openssl req -new -x509 -days 3650 -config "${CWD}/certs/server_ca.cnf" -key "${SERVER_DIR}/ca.key" \
    -out "${SERVER_DIR}/server_ca.pem"

  openssl ecparam -genkey -name prime256v1 | openssl ec -out "${SERVER_DIR}/server.key"
  openssl req -new -config "${CWD}/certs/server.cnf" -key "${SERVER_DIR}/server.key" -out "${SERVER_DIR}/server.csr"
  openssl x509 -req -days 3650 -extfile "${CWD}/certs/server.ext" -in "${SERVER_DIR}/server.csr" -CAcreateserial \
    -CAkey "${SERVER_DIR}/ca.key" -CA "${SERVER_DIR}/server_ca.pem" -out "${SERVER_DIR}/server.crt"
  cat "${SERVER_DIR}/server.crt" "${SERVER_DIR}/server_ca.pem" > "${SERVER_DIR}/server.chain.pem"

  openssl ecparam -genkey -name prime256v1 | openssl ec -out "${DEVICES_DIR}/ca.key"
  openssl req -new -x509 -days 3650 -key "${DEVICES_DIR}/ca.key" -config "${CWD}/certs/device_ca.cnf" \
    -out "${DEVICES_DIR}/ca.crt"

  ${KUBECTL} create secret generic gateway-tls \
    --from-file "${SERVER_DIR}/server.key" \
    --from-file "${SERVER_DIR}/server.chain.pem" \
    --from-file "${SERVER_DIR}/devices/ca.crt"
}

create_configs() {
  ${KUBECTL} get configmap bootstrap-rules &>/dev/null || {
    ${KUBECTL} create configmap bootstrap-rules --from-file config/vaults/bootstrap-rules.json
  }

  declare -a policies=(tuf crypt gateway)
  for policy in "${policies[@]}"; do
    ${KUBECTL} get configmap "${policy}-policy" &>/dev/null || {
      ${KUBECTL} create configmap --from-file "config/vaults/${policy}-policy.hcl" "${policy}-policy"
    }
    ${KUBECTL} get secret "${policy}-tokens" &>/dev/null || {
      ${KUBECTL} create secret generic "${policy}-tokens"
    }
  done
}

create_databases() {
  local pod
  pod=$(wait_for_pods mysql)
  ${KUBECTL} cp "${CWD}/sql" "${pod}:/tmp/"
  ${KUBECTL} exec "${pod}" -- bash -c "mysql -p${DB_PASS} < /tmp/sql/install_plugins.sql || true" 2>/dev/null
  ${KUBECTL} exec "${pod}" -- bash -c "mysql -p${DB_PASS} < /tmp/sql/create_databases.sql"
}

init_vault() {
  local vault=${1}
  local api="http://localhost:8200/v1"

  if [[ $(http "${api}/sys/health" | jq '.initialized') = false ]]; then
    local result
    result=$(http --check-status PUT "${api}/sys/init" \
      secret_shares:="${VAULT_SHARES}" secret_threshold:="${VAULT_THRESHOLD}")
    ${KUBECTL} create secret generic "${vault}-init" \
      --from-literal="root=$(echo "${result}" | jq --raw-output '.root_token')" \
      --from-literal="keys=$(echo "${result}" | jq --raw-output '.keys[]')"
  fi
}

unseal_vault() {
  local vault=${1}
  local pod=${2}

  if ${KUBECTL} get secrets "${vault}-init" &>/dev/null; then
    ${KUBECTL} get secrets "${vault}-init" -o json |
      jq -r .data.keys |
      base64 --decode  |
      awk 'BEGIN {print "export VAULT_ADDR=http://127.0.0.1:8200"}
                 {print "vault unseal "$0}
           END   {print "vault status"}' |
      ${KUBECTL} exec -i "${pod}" sh
  fi
}

start_vaults() {
  create_configs

  for vault in ${VAULTS:-tuf-vault crypt-vault}; do
    apply_template "templates/vaults/${vault}.tmpl.yaml"

    local pod
    pod=$(wait_for_pods "${vault}")
    ${KUBECTL} port-forward "${pod}" 8200:8200 &
    local pid=$!
    trap "kill_pid ${pid}" EXIT
    sleep 3s

    init_vault "${vault}"
    unseal_vault "${vault}" "${pod}"
    kill_pid "${pid}"

    apply_template "templates/jobs/${vault}-bootstrap.tmpl.yaml"
  done
}

start_weave() {
  [[ ${SKIP_WEAVE} == true ]] && return 0;
  apply_template templates/weave
}

start_ingress() {
  [[ ${SKIP_INGRESS} == true ]] && return 0;
  apply_template templates/ingress
}

start_infra() {
  apply_template templates/infra
  wait_for_pods kafka
  create_databases
}

start_services() {
  apply_template templates/services
  get_credentials
}

get_credentials() {
  ${KUBECTL} get secret "user-keys" &>/dev/null && return 0

  ${KUBECTL} proxy --port 8200 &
  local pid=$!
  trap "kill_pid ${pid}" EXIT
  sleep 3s

  local namespace="x-ats-namespace:default"
  local api="http://localhost:8200/api/v1/namespaces/default/services"
  local keyserver="${api}/tuf-keyserver/proxy"
  local reposerver="${api}/tuf-reposerver/proxy"
  local director="${api}/director/proxy"
  local id
  local keys

  retry_command "director" "[[ true = \$(http --print=b ${director}/health \
    | jq --exit-status '.status == \"OK\"') ]]"
  retry_command "keyserver" "[[ true = \$(http --print=b ${keyserver}/health \
    | jq --exit-status '.status == \"OK\"') ]]"
  retry_command "reposerver" "[[ true = \$(http --print=b ${reposerver}/health/dependencies \
    | jq --exit-status '.[].status == \"up\"') ]]"

  id=$(http --ignore-stdin --check-status --print=b POST "${reposerver}/api/v1/user_repo" "${namespace}" | jq --raw-output .)
  http --ignore-stdin --check-status POST "${director}/api/v1/admin/repo" "${namespace}"

  retry_command "keys" "http --ignore-stdin --check-status ${keyserver}/api/v1/root/${id}"
  keys=$(http --ignore-stdin --check-status "${keyserver}/api/v1/root/${id}/keys/targets/pairs")
  echo ${keys} | jq -r 'del(.[0].keyval.private)' | jq -r '.[0]' > "${SERVER_DIR}/targets.pub"
  echo ${keys} | jq -r 'del(.[0].keyval.public)'  | jq -r '.[0]' > "${SERVER_DIR}/targets.sec"

  retry_command "root.json" "http --ignore-stdin --check-status -d -o \"${SERVER_DIR}/root.json\" \
    ${reposerver}/api/v1/user_repo/root.json \"${namespace}\""
  echo "http://tuf-reposerver.${DNS_NAME}" > "${SERVER_DIR}/tufrepo.url"
  echo "https://${SERVER_NAME}:30443" > "${SERVER_DIR}/autoprov.url"
  cat > "${SERVER_DIR}/treehub.json" <<END
{
    "no_auth": true,
    "ostree": {
        "server": "http://treehub.${DNS_NAME}/api/v3/"
    }
}
END

  zip --quiet --junk-paths ${SERVER_DIR}/{credentials.zip,autoprov.url,server_ca.pem,tufrepo.url,targets.pub,targets.sec,treehub.json,root.json}

  kill_pid "${pid}"
  ${KUBECTL} create secret generic "user-keys" --from-literal="id=${id}" --from-literal="keys=${keys}"
}


[ $# -lt 1 ] && { echo "Usage: $0 <command> [<args>]"; exit 1; }
command=$(echo "${1}" | sed 's/-/_/g')

case "${command}" in
  "start_all")
    check_dependencies
    start_weave
    pull_images
    new_server
    start_ingress
    start_infra
    start_vaults
    start_services
    ;;
  "start_weave")
    start_weave
    ;;
  "start_ingress")
    start_ingress
    ;;
  "start_infra")
    start_infra
    ;;
  "start_vaults")
    start_vaults
    ;;
  "new_client")
    new_client
    ;;
  "new_server")
    new_server
    ;;
  "pull_images")
    pull_images
    ;;
  "print_hosts")
    print_hosts
    ;;
  *)
    echo "Unknown command: ${command}"
    exit 1
    ;;
esac
