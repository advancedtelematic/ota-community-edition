#!/usr/bin/env bash

set -uex

export SERVERNAME=${SERVERNAME:-ota.ce}
export DEVICE_ID=${1}
readonly KUBE_IP=$(minikube ip)
export DEVICE_UUID=$(uuidgen)
readonly REGISTRY_HOST=$(kubectl get ingress -o jsonpath --template='{.items[?(@.metadata.name=="device-registry")].spec.rules[0].host}')
readonly SERVER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/../${SERVERNAME}
readonly DEVICES_DIR=${SERVER_DIR}/devices
readonly DIR=${DEVICES_DIR}/${DEVICE_ID}
mkdir -p ${DIR}

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${DIR}/pkey.pem
openssl req -new -config client.cnf -key ${DIR}/pkey.pem -out ${DIR}/${DEVICE_ID}.csr
openssl x509 -req -days 365 -extfile client.ext -in ${DIR}/${DEVICE_ID}.csr -CAkey ${DEVICES_DIR}/ca.key -CA ${DEVICES_DIR}/ca.crt -CAcreateserial -out ${DIR}/client.pem
cat ${DIR}/client.pem ${DEVICES_DIR}/ca.crt > ${DIR}/${DEVICE_ID}.chain.pem
ln -s ${SERVER_DIR}/server_ca.pem ${DIR}/ca.pem

openssl x509 -in ${DIR}/client.pem -text -noout

http PUT http://${KUBE_IP}/api/v1/devices "Host:${REGISTRY_HOST}" deviceUuid="${DEVICE_UUID}" deviceId=${DEVICE_ID} deviceName=${DEVICE_ID} deviceType=Other credentials=@${DIR}/client.pem
