#!/bin/bash
# Distribute the shared CA from ldap1 to ldap2 + ldap3, then run certs.sh on each VM
# with the proper per-node SAN. Run from this directory.
#
# Idempotent. Restarts the openldap container on each VM if its cert was renewed.
set -euo pipefail

cd "$(dirname "$0")"

MODE_DIR="/vagrant/ha-active-passive"
# Per-node SANs - adjust if you change Vagrantfile IPs/hostnames
declare -A NODE_SAN=(
  [ldap1]="DNS:ldap1,DNS:openldap-1,IP:192.168.58.10"
  [ldap2]="DNS:ldap2,DNS:openldap-2,IP:192.168.58.11"
  [ldap3]="DNS:ldap3,DNS:openldap-3,IP:192.168.58.12"
)

echo "=== Step 1: generate CA + cert on ldap1 (CA master) ==="
vagrant ssh ldap1 -c "cd $MODE_DIR && sudo bash certs.sh --san '${NODE_SAN[ldap1]}' --restart --quiet"

echo "=== Step 2: copy CA from ldap1 to host (staging) ==="
TMP_CA=$(mktemp -d)
trap 'rm -rf "$TMP_CA"' EXIT
vagrant ssh ldap1 -c "sudo cat $MODE_DIR/certs/openldapCA.crt" > "$TMP_CA/openldapCA.crt"
vagrant ssh ldap1 -c "sudo cat $MODE_DIR/certs/openldapCA.key" > "$TMP_CA/openldapCA.key"
chmod 600 "$TMP_CA/openldapCA.key"

echo "=== Step 3: push CA + generate per-node cert on peers ==="
for vm in ldap2 ldap3; do
  echo "--- $vm ---"
  # Stage CA into the VM under a temp dir, then run certs.sh --ca-from
  vagrant ssh "$vm" -c "sudo mkdir -p /tmp/ca-seed && sudo chmod 700 /tmp/ca-seed"
  vagrant ssh "$vm" -- "sudo tee /tmp/ca-seed/openldapCA.crt > /dev/null" < "$TMP_CA/openldapCA.crt"
  vagrant ssh "$vm" -- "sudo tee /tmp/ca-seed/openldapCA.key > /dev/null" < "$TMP_CA/openldapCA.key"
  vagrant ssh "$vm" -c "sudo chmod 600 /tmp/ca-seed/openldapCA.key && \
    cd $MODE_DIR && sudo bash certs.sh \
      --ca-from /tmp/ca-seed \
      --san '${NODE_SAN[$vm]}' \
      --restart --quiet && \
    sudo rm -rf /tmp/ca-seed"
done

echo
echo "=== Verify chain on each VM ==="
for vm in ldap1 ldap2 ldap3; do
  printf "%s: " "$vm"
  vagrant ssh "$vm" -c "sudo openssl verify -CAfile $MODE_DIR/certs/openldapCA.crt $MODE_DIR/certs/openldap.crt"
done
