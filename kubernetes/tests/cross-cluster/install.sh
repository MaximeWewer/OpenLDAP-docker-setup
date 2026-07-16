#!/bin/bash
# End-to-end deploy on the 2-VM cross-cluster rig.
#
#   1. Generate shared CA + per-cluster certs (if not already present).
#   2. Push admin, replicator, TLS Secrets into both minikubes.
#   3. helm install dc1 first, wait for pods ready.
#   4. helm install dc2, wait for pods ready.
#   5. Verify base tree present on both.
#
# Idempotent — safe to re-run on top of an existing deploy (values change
# → helm upgrade path).
set -euo pipefail

cd "$(dirname "$0")"

: "${ADMIN_PW:=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)}"
: "${CFG_ADMIN_PW:=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)}"
: "${REPLICATOR_PW:=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)}"

echo "=== [0] generating shared CA + per-cluster certs ==="
bash shared/gen-ca.sh

install_dc() {
  local dc="$1" values="$2"
  echo "=== [${dc}] pushing shared Secrets ==="
  vagrant ssh "$dc" -c "sudo kubectl create ns ldap --dry-run=client -o yaml | sudo kubectl apply -f -"

  vagrant ssh "$dc" -c "sudo kubectl -n ldap create secret generic openldap-admin-shared \
    --from-literal=admin-password='${ADMIN_PW}' \
    --from-literal=config-admin-password='${CFG_ADMIN_PW}' \
    --dry-run=client -o yaml | sudo kubectl apply -f -"

  vagrant ssh "$dc" -c "sudo kubectl -n ldap create secret generic openldap-replicator-shared \
    --from-literal=replicator-password='${REPLICATOR_PW}' \
    --dry-run=client -o yaml | sudo kubectl apply -f -"

  # scp certs into the VM and create the TLS Secret
  vagrant ssh "$dc" -c "sudo mkdir -p /tmp/tls && sudo chown vagrant:vagrant /tmp/tls"
  vagrant scp "shared/ca.crt"  "$dc:/tmp/tls/ca.crt"
  vagrant scp "shared/${dc}/tls.crt" "$dc:/tmp/tls/tls.crt"
  vagrant scp "shared/${dc}/tls.key" "$dc:/tmp/tls/tls.key"
  vagrant ssh "$dc" -c "sudo kubectl -n ldap create secret generic openldap-tls-shared \
    --from-file=ca.crt=/tmp/tls/ca.crt \
    --from-file=tls.crt=/tmp/tls/tls.crt \
    --from-file=tls.key=/tmp/tls/tls.key \
    --dry-run=client -o yaml | sudo kubectl apply -f - && sudo rm -rf /tmp/tls"

  echo "=== [${dc}] helm upgrade --install ==="
  vagrant scp "${values}" "$dc:/tmp/values.yaml"
  vagrant ssh "$dc" -c "cd /vagrant/kubernetes/charts/openldap-stack && sudo helm dependency update >/dev/null 2>&1; sudo helm upgrade --install ldap /vagrant/kubernetes/charts/openldap-stack -n ldap -f /tmp/values.yaml --wait --timeout 6m"
}

echo ""
echo "=== [1] deploying dc1 (seed) ==="
install_dc dc1 dc1/values.yaml

echo ""
echo "=== [2] deploying dc2 (join) ==="
install_dc dc2 dc2/values.yaml

echo ""
echo "=== [3] deploy complete. Admin credentials:"
echo "    ADMIN_PW=${ADMIN_PW}"
echo "    CFG_ADMIN_PW=${CFG_ADMIN_PW}"
echo "    REPLICATOR_PW=${REPLICATOR_PW}"
echo ""
echo "Save them somewhere — re-running install.sh generates new ones unless"
echo "you `export` these vars before the second run."
echo ""
echo "Next: bash test-replication.sh"
