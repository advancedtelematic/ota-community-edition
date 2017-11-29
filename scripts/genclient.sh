#!/usr/bin/env bash

set -uex

readonly DEVICE_SUBJ=/CN=${1}
readonly DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/../out

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${DIR}/client.key
openssl req -new -config client.cnf -subj ${DEVICE_SUBJ} -key ${DIR}/client.key -out ${DIR}/client.csr
openssl x509 -req -days 365 -extfile client.ext -in ${DIR}/client.csr -CAkey ${DIR}/ca.key -CA ${DIR}/ca.crt -CAcreateserial -out ${DIR}/client.crt
cat ${DIR}/client.crt ${DIR}/ca.crt > ${DIR}/client.chain.pem

openssl req -in ${DIR}/client.csr -text -noout
openssl x509 -in ${DIR}/client.crt -text -noout
