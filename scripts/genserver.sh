#!/usr/bin/env bash

set -euo pipefail

export SERVERNAME=${SERVERNAME:-ota.ce}
readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly SERVER_DIR="${SCRIPT_DIR}/../${SERVERNAME}"
mkdir -p ${SERVER_DIR}

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${SERVER_DIR}/ca.key
openssl req -new -x509 -days 3650 -config ${SCRIPT_DIR}/server_ca.cnf -key ${SERVER_DIR}/ca.key \
  -out ${SERVER_DIR}/server_ca.pem

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${SERVER_DIR}/server.key
openssl req -new -config ${SCRIPT_DIR}/server.cnf -key ${SERVER_DIR}/server.key -out ${SERVER_DIR}/server.csr
openssl x509 -req -days 3650 -extfile ${SCRIPT_DIR}/server.ext -in ${SERVER_DIR}/server.csr -CAcreateserial \
  -CAkey ${SERVER_DIR}/ca.key -CA ${SERVER_DIR}/server_ca.pem -out ${SERVER_DIR}/server.crt
cat ${SERVER_DIR}/server.crt ${SERVER_DIR}/server_ca.pem > ${SERVER_DIR}/server.chain.pem

readonly DEVICES_DIR=${SERVER_DIR}/devices
mkdir -p ${DEVICES_DIR}

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${DEVICES_DIR}/ca.key
openssl req -new -x509 -days 3650 -key ${DEVICES_DIR}/ca.key -config ${SCRIPT_DIR}/device_ca.cnf \
  -out ${DEVICES_DIR}/ca.crt

