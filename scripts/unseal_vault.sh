#!/bin/sh

set -euo pipefail


init_key=${INIT_KEY:-/init.key}

vault init -check 2>/dev/null && exit 0
vault init -key-shares=1 -key-threshold=1 > "${init_key}"

root_key=$(awk -F': ' '/^Initial Root Token/{e=0; print $2; exit} {e=1} END{exit e}' "${init_key}")
unseal_key=$(awk -F': ' '/^Unseal Key 1/{e=0; print $2; exit} {e=1} END{exit e}' "${init_key}")
vault unseal "${unseal_key}"
export VAULT_TOKEN="$root_key"

vault policy-write tuf - <<END
path "ota-tuf/keys/*" {
  policy = "write"
}
END

vault mount -path /ota-tuf/keys generic
vault token-create -policy="tuf" -period="72h"
