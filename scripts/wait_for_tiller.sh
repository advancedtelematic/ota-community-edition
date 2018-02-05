#!/usr/bin/env bash

[[ ${DEBUG} = true ]] && set -x
set -euo pipefail

readonly KUBECTL="${KUBECTL:-kubectl}"

try() {
  local name=$1
  local output=$2
  local command=${@:3}
  local n=0
  local max=100
  while true; do
    if ${output}; then
      eval "${command}" && return 0
    else
      eval "${command}" &> /dev/null && return 0
    fi
    [[ $((n++)) -gt $max ]] && return 1
    echo >&2 "Waiting for $name"
    sleep 5s
  done
}

try Tiller false 'kubectl get pods -n kube-system -l app=helm,name=tiller -o=jsonpath="{.items[0].status.phase}" | grep Running'
