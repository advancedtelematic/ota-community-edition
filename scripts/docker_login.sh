#!/bin/bash

set -euo pipefail

: "${DOCKER_USER:?}"
: "${DOCKER_PASS:?}"

docker_config=$(cat <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$(echo -n "${DOCKER_USER}:${DOCKER_PASS}" | base64 | tr -d '\n')"
    }
  }
}
EOF
)

kubectl create --filename - <<EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: docker-registry-key
data:
  .dockerconfigjson: $(echo -n "${docker_config}" | base64 | tr -d '\n')
EOF
