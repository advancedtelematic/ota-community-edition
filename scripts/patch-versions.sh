#!/bin/bash

# Usage

# ```
# echo "advancedtelematic/treehub:0.1.25 advancedtelematic/web-events:0.0.23" | ./scripts/patch-versions.sh
# ```
#
# or
#
# ```
# echo "advancedtelematic/treehub:0.1.25
#       advancedtelematic/web-events:0.0.23
#        ..." | ./scripts/patch-versions.sh`
# ```
#
# or
#
# ```
# echo advancedtelematic/treehub:0.1.25 advancedtelematic/web-events:0.0.23 > versions.txt
# ./scripts/patch-versions.sh versions.txt
# ```

function get_deployment_tag {
  deployments=$(echo "$1" | awk '
  /ota-plus-web/    { print "ota-app ota-app-connect" }
  /auth-plus/       { print "ota-auth-plus" }
  /campaigner/      { print "ota-campaigner ota-campaigner-daemon" }
  /device-registry/ { print "ota-device-registry" }
  /director/        { print "ota-director ota-director-daemon" }
  /treehub/         { print "ota-treehub" }
  /tuf-reposerver/  { print "ota-tuf-reposerver ota-tuf-reposerver-internal" }
  /tuf-keyserver/   { print "ota-tuf-keyserver ota-tuf-keyserver-daemon" }
  /web-events/      { print "ota-web-events" }
  ')

  echo "$deployments"
}

while read docker_tag
do
  deployments=$(get_deployment_tag "$docker_tag")
  for deploy in $deployments
  do
    kubectl set image deployment/"$deploy" "*=$docker_tag"
  done
done < "${1:-/dev/stdin}"
