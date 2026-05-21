#!/bin/bash
# Vagrant provisioner: install Docker + run ha-active-active/setup-node.sh on this VM.
set -euo pipefail

: "${SERVER_ID:?}"
: "${NODE_URIS:?}"

export DEBIAN_FRONTEND=noninteractive

# === Install Docker if missing ===
if ! command -v docker >/dev/null 2>&1; then
  echo "=== Installing Docker ==="
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg python3 ldap-utils
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  usermod -aG docker vagrant
fi
apt-get install -y -qq ldap-utils python3 || true

HA_DIR=/vagrant/ha-active-active
cd "$HA_DIR"

cat > .env <<EOF
SERVER_ID=${SERVER_ID}
NODE_URIS=${NODE_URIS}
REPLICATOR_DN=cn=replicator,ou=service-accounts,dc=example,dc=org
REPLICATOR_PASSWORD=replicatorpassword
HAPROXY_STATS_USER=admin
HAPROXY_STATS_PASSWORD=admin
ENABLE_PHPLDAPADMIN=${ENABLE_PHPLDAPADMIN:-false}
EOF

# === Wait for node1 (peers need a sync source) ===
if [ "$SERVER_ID" != "1" ]; then
  NODE1_HOST=$(echo "$NODE_URIS" | cut -d, -f1 | sed -E 's#ldap://##; s#:.*##')
  echo "=== Waiting for node1 ($NODE1_HOST:389) ==="
  for i in $(seq 1 60); do
    if (echo > /dev/tcp/${NODE1_HOST}/389) 2>/dev/null; then echo "node1 reachable."; break; fi
    [ "$i" -eq 60 ] && { echo "node1 unreachable after 60s"; exit 1; }
    sleep 2
  done
fi

RESET_FLAG=""
if [ -d "$HA_DIR/data/slapd.d" ] && [ "$(ls -A $HA_DIR/data/slapd.d 2>/dev/null)" ]; then
  RESET_FLAG="--reset"
fi
bash "$HA_DIR/setup-node.sh" $RESET_FLAG
