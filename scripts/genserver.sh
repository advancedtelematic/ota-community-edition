#!/usr/bin/env bash

set -ue

readonly DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/../out
mkdir -p ${DIR}

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${DIR}/ca.key
openssl req -new -x509 -days 365 -key ${DIR}/ca.key -out ${DIR}/ca.crt -config ca.cnf

openssl ecparam -genkey -name prime256v1 | openssl ec -out ${DIR}/server.key
openssl req -new -config server.cnf -key ${DIR}/server.key -out ${DIR}/server.csr
openssl x509 -req -days 365 -extfile server.ext -in ${DIR}/server.csr -CAkey ${DIR}/ca.key -CA ${DIR}/ca.crt -CAcreateserial -out ${DIR}/server.crt
cat ${DIR}/server.crt ${DIR}/ca.crt > ${DIR}/server.chain.pem

openssl req -in ${DIR}/server.csr -text -noout
openssl x509 -in ${DIR}/server.crt -text -noout