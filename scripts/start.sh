#!/usr/bin/env bash

[[ ${DEBUG} = true ]] && set -x
set -euo pipefail

: "${DOMAIN:?}" # Check DOMAIN is set

readonly DEPENDENCIES=${DEPENDENCIES:-bash curl make http jq yq kubectl helm openssl}
readonly NETWORK=${NETWORK:-true}
readonly KUBECTL=${KUBECTL:-kubectl}
readonly CWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly LOG_OUTPUT=${LOG_OUTPUT:-false}
readonly DB_PASS=${DB_PASS:-root}
readonly VAULT_SHARES=${VAULT_SHARES:-5}
readonly VAULT_THRESHOLD=${VAULT_THRESHOLD:-3}

export   SERVER_NAME=${SERVER_NAME:-ota.ce}
readonly DNS_NAME=${DNS_NAME:-ota.local}
readonly SERVER_DIR=${SERVER_DIR:-${CWD}/../generated/${SERVER_NAME}}
readonly CHART_DIR=${CHART_DIR:-${CWD}/../charts/}
readonly PROXY_PORT=${PROXY_PORT:-8200}
readonly NAMESPACE=${NAMESPACE:-default}
readonly DEVICES_DIR=${DEVICES_DIR:-${SERVER_DIR}/devices}

# Location of `aktualizr` configuration files.
readonly CLIENT_CONFIG_BASE_DIR=${CLIENT_CONFIG_BASE_DIR:-"${HOME}/localtest"}

# Location of `aktualizr`. It's a part of `aktualizr` package.
readonly AKTUALIZR_PATH=${AKTUALIZR_PATH:-"/usr/bin/aktualizr"}

# Location of `aktualizr-cert-provider`. It's a part of `garage-deploy` package.
readonly CERT_PROVIDER_PATH=${CERT_PROVIDER_PATH:-"/usr/bin/aktualizr-cert-provider"}

# $1 = # of seconds
# $@ = What to print after "Waiting n seconds"
countdown() {
  secs=$1
  shift
  msg=$@
  while [[ ${secs} -gt 0 ]]
  do
    printf "\r\033[KWaiting %.d seconds $msg" $((secs--))
    sleep 1s
  done
  echo
}

kill_pid() {
  local pid=${1}
  kill -0 "${pid}" 2>/dev/null || return 0
  kill -9 "${pid}"
}

check_dependencies() {
  for cmd in ${DEPENDENCIES}; do
    [[ $(command -v "${cmd}") ]] || {
      echo "Please install '${cmd}'."
      exit 1
    }
  done
}

log_output() {
  [[ ${LOG_OUTPUT} == true ]] || return 0

  local action=$1
  local start_time=$(TZ=UTC date +"%Y-%m-%dT%H:%M:%SZ")
  local log_dir="${CWD}/../logs/$(echo ${start_time} | sed 's/[^0-9]*//g')-${action}"
  mkdir -p "${log_dir}"

  for namespace in ${LOG_NAMESPACES:-default ingress-nginx}; do
    local kubectl="${KUBECTL} --namespace=${namespace}"
    for pod in $(${kubectl} get pods -o jsonpath='{.items..metadata.name}'); do
      ${kubectl} describe pod "${pod}" > "${log_dir}/${pod}.desc"
      ${kubectl} logs "${pod}" --timestamps --since-time="${start_time}" > "${log_dir}/${pod}.logs" || true
    done
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
  local namespace=${2-default}
  ${KUBECTL} get pods -n ${namespace} --selector=app="${app}" --output jsonpath='{.items[0].metadata.name}'
}

wait_for_pods() {
  local app=${1}
  local namespace=${2-default}
  retry_command "${app}" "[[ true = \$(${KUBECTL} get pods -n ${namespace} --selector=app=${app} --output json \
    | jq --exit-status '(.items | length > 0) and ([.items[].status.containerStatuses[].ready] | all)') ]]"
  first_pod "${app}" "${namespace}"
}

# Add `tuf-reposerver.ota.local`
print_hosts() {
  retry_command "ingress" "${KUBECTL} get ingress -o json \
    | jq --exit-status '.items[0].status.loadBalancer.ingress'"
  ${KUBECTL} get ingress --no-headers | awk -v ip=$(minikube ip) '{print ip " " $2}'
}

declare -A Versions

[[ -f versions ]] && eval $(cat versions)

get_latest_version() {
  svcName="$1"
  if [ ${Versions[$svcName]+"not_found"} ]
  then
    echo ${Versions[$svcName]}
  else
    remoteDir="s3://ats-build-artifacts/Staging_${svcName}/Staging_Deploy_${svcName}Deploy/"
    imgTagFile=/tmp/image.tag.txt
    rm -f $imgTagFile

    # latestBuildDir is highest number directory and should contain "artifacts.txt" file
    if latestBuildDir=$(s3cmd ls $remoteDir | awk -F/ '{print $6}' | sort -n | tail -1)  &&
      s3cmd get ${remoteDir}${latestBuildDir}/artifacts.txt $imgTagFile > /dev/null
    then
      cat $imgTagFile
    else
      echo "latest"
    fi
  fi
}

start_ingress() {
  kubectl apply -f ./manifests/ingress/ingress.yaml
  log_output start_ingress
}

start_infra() {
  wait_for_pods helm kube-system
  helm upgrade --install ota-zookeeper ${CHART_DIR}/ota-zookeeper
  helm upgrade --install ota-mariadb ${CHART_DIR}/ota-mariadb
  helm upgrade --install ota-kafka ${CHART_DIR}/ota-kafka
  helm upgrade --install ota-mariadb-bootstrap ${CHART_DIR}/ota-mariadb-bootstrap

  log_output start_infra
}

delete_infra() {
  helm del --purge ota-zookeeper || true
  helm del --purge ota-mariadb || true
  helm del --purge ota-mariadb-bootstrap || true
  helm del --purge ota-kafka || true
  log_output stop_infra
}

delete_services() {
  helm del --purge ota-api-gateway || true
  helm del --purge ota-app || true
  helm del --purge ota-campaigner || true
  helm del --purge ota-device-gateway || true
  helm del --purge ota-device-registry || true
  helm del --purge ota-director || true
  helm del --purge ota-treehub || true
  helm del --purge ota-tuf-keyserver || true
  helm del --purge ota-tuf-reposerver || true
  helm del --purge ota-web-events || true
}


start_services() {
  if ! kubectl get secret tls-cert-key
  then
    certname=tls-cert-key
    certfile=/tmp/tls.cert
    keyfile=/tmp/tls.key
    openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout ${keyfile} -out ${certfile} -subj "/CN=${DOMAIN}/O=${DOMAIN}"
    kubectl create secret tls ${certname} --key ${keyfile} --cert ${certfile}
  fi

  upgrade_gateway
  upgrade_ota_api_gateway
  upgrade_ota_app
  upgrade_ota_campaigner
  upgrade_ota_device_registry
  upgrade_ota_director
  upgrade_ota_treehub
  upgrade_ota_tuf_keyserver
  upgrade_ota_tuf_reposerver
  upgrade_ota_web_events

  get_credentials
  log_output start_services
}

get_credentials() {
  ${KUBECTL} get secret "user-keys" &>/dev/null && return 0

  ${KUBECTL} proxy --port "${PROXY_PORT}" &
  local pid=$!
  trap "kill_pid ${pid}" EXIT
  sleep 3s

  local namespace="x-ats-namespace:default"
  local api="http://localhost:${PROXY_PORT}/api/v1/namespaces/${NAMESPACE}/services"
  local keyserver="${api}/ota-tuf-keyserver:80/proxy"
  local reposerver="${api}/ota-tuf-reposerver:80/proxy"
  local reposerver_internal="${api}/ota-tuf-reposerver-internal:80/proxy"
  local director="${api}/ota-director:80/proxy"
  local id
  local keys

  retry_command "director" "[[ true = \$(http --print=b GET ${director}/health \
    | jq --exit-status '.status == \"OK\"') ]]"
  retry_command "keyserver" "[[ true = \$(http --print=b GET ${keyserver}/health \
    | jq --exit-status '.status == \"OK\"') ]]"
  retry_command "reposerver" "[[ true = \$(http --print=b GET ${reposerver}/health \
    | jq --raw-input '. == \"alive\"') ]]"

  # Query internal reposerver since it points to the unauthenticated tuf-reposerver pod
  countdown 150 "to start ota-tuf-reposerver-internal"
  id=$(http --ignore-stdin --check-status --print=b POST "${reposerver_internal}/api/v1/user_repo" "${namespace}" | jq --raw-output .)
  http --ignore-stdin --check-status POST "${director}/api/v1/admin/repo" "${namespace}"

  retry_command "keys" "http --ignore-stdin --check-status GET ${keyserver}/api/v1/root/${id}"
  keys=$(http --ignore-stdin --check-status GET "${keyserver}/api/v1/root/${id}/keys/targets/pairs")
  echo ${keys} | jq '.[0] | {keytype, keyval: {public: .keyval.public}}'   > "${SERVER_DIR}/targets.pub"
  echo ${keys} | jq '.[0] | {keytype, keyval: {private: .keyval.private}}' > "${SERVER_DIR}/targets.sec"

  retry_command "root.json" "http --ignore-stdin --check-status -d GET \
    ${reposerver_internal}/api/v1/user_repo/root.json \"${namespace}\"" && \
    http --ignore-stdin --check-status -d -o "${SERVER_DIR}/root.json" GET \
    ${reposerver_internal}/api/v1/user_repo/root.json "${namespace}"

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

  openssl pkcs12 -export -out "${SERVER_DIR}/autoprov_credentials.p12" \
  -in "${SERVER_DIR}/server.chain.pem" \
  -inkey "${SERVER_DIR}/server.key" \
  -CAfile "${SERVER_DIR}/devices/ca.crt" #-chain
  zip --quiet --junk-paths ${SERVER_DIR}/{credentials.zip,autoprov.url,server_ca.pem,tufrepo.url,targets.pub,targets.sec,treehub.json,root.json,autoprov_credentials.p12}

  kill_pid "${pid}"
  ${KUBECTL} create secret generic "user-keys" --from-literal="id=${id}" --from-literal="keys=${keys}"
}

upgrade_ota_api_gateway() {
  helm upgrade --install ota-api-gateway ${CHART_DIR}/ota-api-gateway --set \
ingress.hosts={api.$DOMAIN}\
,configMap.TUF_REPOSERVER_HOST_PUB=repo.$DOMAIN\
,configMap.TREEHUB_HOST_PUB=treehub.$DOMAIN
}

upgrade_ota_app() {
  if [[ -f .connect-creds.yaml ]]
  then
    connectSettings="-f .connect-creds.yaml --set ingress.tls.connect[0].secretName=tls-cert-key --set configMap.connect.enabled=true --set configMap.WS_PORT=433 --set configMap.WS_SCHEME=wss"
  else
    connectSettings=""
  fi
  helm upgrade --install ota-app ${CHART_DIR}/ota-app --set \
image.tag=${1-$(get_latest_version App)}\
,ingress.hosts.atsgarage={app.$DOMAIN}\
,ingress.hosts.connect={connect.$DOMAIN}\
,withAuthPlus=false\
,configMap.AUTH0_TOKEN_AUDIENCE=http://auth-plus.$DOMAIN\
,configMap.TREEHUB_HOST_PUB=treehub.$DOMAIN\
,configMap.TUF_REPOSERVER_HOST_PUB=repo.$DOMAIN\
,configMap.WS_HOST=web-events.$DOMAIN\
,configMap.API_GATEWAY_HOST=api.$DOMAIN\
,configMap.OIDC_NS_PROVIDER=com.advancedtelematic.auth.oidc.ConfiguredNamespace\
,configMap.OIDC_LOGIN_ACTION=com.advancedtelematic.auth.garage.NoLoginAction\
,configMap.OIDC_LOGOUT_ACTION=com.advancedtelematic.auth.garage.NoLogoutAction\
,configMap.OIDC_TOKEN_EXCHANGE=com.advancedtelematic.auth.NoExchange\
,configMap.OIDC_TOKEN_VERIFICATION=com.advancedtelematic.auth.oidc.TokenValidityCheck\
,configMap.atsgarage.AUTH0_CALLBACK_URL=http://app.$DOMAIN/callback\
,configMap.connect.AUTH0_CALLBACK_URL=https://connect.$DOMAIN/callback ${connectSettings}
}

upgrade_gateway() {
  helm del --purge gateway || true
  helm upgrade --install gateway ${CHART_DIR}/gateway --set \
image.tag=${1-$(get_latest_version Gateway)}\
,serverName=gateway
}

upgrade_ota_campaigner() {
  helm upgrade --install ota-campaigner ${CHART_DIR}/ota-campaigner --set \
image.tag=${1-$(get_latest_version Campaigner)}\
,ingress.hosts={campaigner.$DOMAIN}
}

upgrade_ota_device_registry() {
  helm upgrade --install ota-device-registry ${CHART_DIR}/ota-device-registry --set \
image.tag=${1-$(get_latest_version DeviceRegistry)}\
,ingress.hosts={device-registry.$DOMAIN}
}

upgrade_ota_director() {
  helm upgrade --install ota-director ${CHART_DIR}/ota-director --set \
image.tag=${1-$(get_latest_version Director)}\
,ingress.hosts={director.$DOMAIN}
}

upgrade_ota_treehub() {
  helm upgrade --install ota-treehub ${CHART_DIR}/ota-treehub --set \
image.tag=${1-$(get_latest_version Treehub)}\
,ingress.hosts={treehub.$DOMAIN}
}

upgrade_ota_tuf_keyserver() {
  helm upgrade --install ota-tuf-keyserver ${CHART_DIR}/ota-tuf-keyserver --set \
image.tag=${1-$(get_latest_version OtaTuf)}\
,ingress.hosts={keyserver.$DOMAIN}
}

upgrade_ota_tuf_reposerver() {
  helm upgrade --install ota-tuf-reposerver ${CHART_DIR}/ota-tuf-reposerver --set \
image.tag=${1-$(get_latest_version OtaTuf)}\
,ingress.hosts={repo.$DOMAIN}\
,ingress.internalHosts={repo-internal.$DOMAIN}
}

upgrade_ota_web_events() {
  if [[ -f .connect-creds.yaml ]]
  then
    connectSettings="--set ingress.tls[0].secretName=tls-cert-key"
  else
    connectSettings=""
  fi
  helm upgrade --install ota-web-events ${CHART_DIR}/ota-web-events --set \
image.tag=${1-$(get_latest_version WebEvents)}\
,withAuthPlus=false\
,ingress.hosts={web-events.$DOMAIN} ${connectSettings}
}

start_weave() {
  kubectl apply -f ./manifests/weave/1.10.yaml
  log_output start_weave
}

start_helm() {
  helm init
  wait_for_pods helm kube-system

  if ! ${KUBECTL} get serviceaccount tiller --namespace kube-system &>/dev/null; then
    ${KUBECTL} create serviceaccount --namespace kube-system tiller
    ${KUBECTL} create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    ${KUBECTL} patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
  fi

  log_output start_helm
}

new_client() {
  export DEVICE_UUID=${DEVICE_UUID:-$(uuidgen | tr "[:upper:]" "[:lower:]")}
  local device_id=${DEVICE_ID:-${DEVICE_UUID}}
  local device_dir="${DEVICES_DIR}/${DEVICE_UUID}"
  mkdir -p "${device_dir}"

  ${KUBECTL} proxy --port "${PROXY_PORT}" &
  local pid=$!
  trap "kill_pid ${pid}" EXIT
  sleep 3s

  local gateway=${GATEWAY_ADDR:-$(${KUBECTL} get nodes --output jsonpath \
    --template='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}
  local addr=${DEVICE_ADDR:-localhost}
  local port=${DEVICE_PORT:-2222}
  local options="-o StrictHostKeyChecking=no"

  ssh ${options} "root@${addr}" -p "${port}" "echo \"${gateway} ota.ce\" >> /etc/hosts"

  local tmp_dir=$(mktemp -d)

  ${CERT_PROVIDER_PATH} \
  --credentials "${SERVER_DIR}/credentials.zip" \
  --root-ca \
  --server-url \
  --fleet-ca "${SERVER_DIR}/devices/ca.crt" \
  --fleet-ca-key "${SERVER_DIR}/devices/ca.key" \
  --local "${tmp_dir}" \
  --directory /

  scp -P "${port}" ${options} "${tmp_dir}/client.pem" "root@${addr}:/var/sota/import/"
  scp -P "${port}" ${options} "${tmp_dir}/pkey.pem" "root@${addr}:/var/sota/import/"
  scp -P "${port}" ${options} "${tmp_dir}/root.crt" "root@${addr}:/var/sota/import/"
  scp -P "${port}" ${options} "${tmp_dir}/gateway.url" "root@${addr}:/var/sota/import/"

  local api="http://localhost:${PROXY_PORT}/api/v1/namespaces/${NAMESPACE}/services"
  http --ignore-stdin PUT "${api}/ota-device-registry:80/proxy/api/v1/devices" \
    credentials=@"${tmp_dir}/client.pem" \
    deviceUuid="${DEVICE_UUID}" \
    deviceId="${device_id}" \
    deviceName="${device_id}" \
    deviceType=Other
  kill_pid "${pid}"

}

new_server() {
  ${KUBECTL} get secret gateway-tls &>/dev/null && return 0
  mkdir -p "${SERVER_DIR}" "${DEVICES_DIR}"

  # This is a tag for including a chunk of code in the docs. Don't remove. tag::genserverkeys[]
  openssl ecparam -genkey -name prime256v1 | openssl ec -out "${SERVER_DIR}/ca.key"
  openssl req -new -x509 -days 3650\
    -config "${CWD}/certs/server_ca.cnf" \
    -key "${SERVER_DIR}/ca.key" \
    -out "${SERVER_DIR}/server_ca.pem"

  openssl ecparam -genkey -name prime256v1 | openssl ec -out "${SERVER_DIR}/server.key"

  openssl req -new \
    -config "${CWD}/certs/server.cnf" \
    -key "${SERVER_DIR}/server.key" \
    -out "${SERVER_DIR}/server.csr"

  openssl x509 -req -days 3650 \
    -extfile "${CWD}/certs/server.ext" \
    -in "${SERVER_DIR}/server.csr" -CAcreateserial \
    -CAkey "${SERVER_DIR}/ca.key" \
    -CA "${SERVER_DIR}/server_ca.pem" \
    -out "${SERVER_DIR}/server.crt"
  cat "${SERVER_DIR}/server.crt" "${SERVER_DIR}/server_ca.pem" > "${SERVER_DIR}/server.chain.pem"

  openssl ecparam -genkey -name prime256v1 | openssl ec -out "${DEVICES_DIR}/ca.key"
  openssl req -new -x509 -days 3650 -key "${DEVICES_DIR}/ca.key" -config "${CWD}/certs/device_ca.cnf" \
    -out "${DEVICES_DIR}/ca.crt"
  # end::genserverkeys[]

  ${KUBECTL} create secret generic gateway-tls \
    --from-file "${SERVER_DIR}/server.key" \
    --from-file "${SERVER_DIR}/server.chain.pem" \
    --from-file "${SERVER_DIR}/devices/ca.crt"
}

new_local_client() {
  mkdir ${CLIENT_CONFIG_BASE_DIR} || true
  cat > "${CLIENT_CONFIG_BASE_DIR}/sota-local.toml" <<END
[tls]
server_url_path = "${CLIENT_CONFIG_BASE_DIR}/import/gateway.url"

[provision]
provision_path = "${CLIENT_CONFIG_BASE_DIR}/credentials.zip"
primary_ecu_hardware_id = "desktop"

[storage]
type = "sqlite"
path = "${CLIENT_CONFIG_BASE_DIR}/var_sota"
sqldb_path = "${CLIENT_CONFIG_BASE_DIR}/var_sota/sql.db"

[pacman]
type = "none"

[import]
base_path = "${CLIENT_CONFIG_BASE_DIR}/import/"
tls_cacert_path = "root.crt"
tls_clientcert_path = "client.pem"
tls_pkey_path = "pkey.pem"
END

  cp "${SERVER_DIR}/credentials.zip" \
  "${SERVER_DIR}/devices/ca.crt" \
  "${SERVER_DIR}/devices/ca.key" \
  ${CLIENT_CONFIG_BASE_DIR}

  ${CERT_PROVIDER_PATH} \
  --credentials "${CLIENT_CONFIG_BASE_DIR}/credentials.zip" \
  --root-ca \
  --server-url \
  --fleet-ca "${CLIENT_CONFIG_BASE_DIR}/ca.crt" \
  --fleet-ca-key "${CLIENT_CONFIG_BASE_DIR}/ca.key" \
  --local "${CLIENT_CONFIG_BASE_DIR}/import" \
  --directory /

  sudo ${AKTUALIZR_PATH} --loglevel 0 -c "${CLIENT_CONFIG_BASE_DIR}/sota-local.toml"
}

[ $# -lt 1 ] && { echo "Usage: $0 <command> [<args>]"; exit 1; }
command=$1 && shift

case "${command}" in
  "start_all")
    check_dependencies
    start_helm
    start_weave
    new_server
    start_ingress
    start_infra
    start_services
    ;;
  "start_weave")
    start_weave
    ;;
  "start_infra")
    start_infra
    ;;
  "start_ingress")
    start_ingress
    ;;
  "start_services")
    start_services
    ;;
  "new_client")
    new_client
    ;;
  "new_local_client")
    new_local_client
    ;;
  "delete_services")
    delete_services
    ;;
  "delete_infra")
    delete_infra
    ;;
  "print_hosts")
    print_hosts
    ;;

  *)
    if [ ${command} == "upgrade" -a $# -ge 1 ]; then
      chartname=$(echo $1 | tr - _) && shift
      ${command}_$chartname $*
    else
      echo "Unknown command: ${command}"
      exit 1
    fi
    ;;
esac
