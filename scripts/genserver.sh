#!/usr/bin/env bash

set -ue

export SERVERNAME=${SERVERNAME:-ota.ce}
readonly SERVER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/../${SERVERNAME}
mkdir -p ${SERVER_DIR}

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${SERVER_DIR}/ca.key
openssl req -new -x509 -days 3650 -key ${SERVER_DIR}/ca.key -out ${SERVER_DIR}/server_ca.pem -config server_ca.cnf

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${SERVER_DIR}/server.key
openssl req -new -config server.cnf -key ${SERVER_DIR}/server.key -out ${SERVER_DIR}/server.csr
openssl x509 -req -days 3650 -extfile server.ext -in ${SERVER_DIR}/server.csr -CAkey ${SERVER_DIR}/ca.key -CA ${SERVER_DIR}/server_ca.pem -CAcreateserial -out ${SERVER_DIR}/server.crt
cat ${SERVER_DIR}/server.crt ${SERVER_DIR}/server_ca.pem > ${SERVER_DIR}/server.chain.pem

readonly DEVICES_DIR=${SERVER_DIR}/devices
mkdir -p ${DEVICES_DIR}

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${DEVICES_DIR}/ca.key
openssl req -new -x509 -days 3650 -key ${DEVICES_DIR}/ca.key -out ${DEVICES_DIR}/ca.crt -config device_ca.cnf

echo https://${SERVERNAME}:30443 > ${SERVER_DIR}/autoprov.url
zip -qj ${SERVER_DIR}/credentials.zip ${SERVER_DIR}/autoprov.url ${SERVER_DIR}/server_ca.pem
