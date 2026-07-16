#!/bin/bash
# Reset both VMs to a post-`vagrant up` state: uninstall the chart,
# wipe PVCs + Secrets, leave the minikube cluster itself running.
# Use `vagrant destroy -f` from this directory for a full teardown.
set -euo pipefail

cd "$(dirname "$0")"

for dc in dc1 dc2; do
  echo "=== [${dc}] uninstalling release ==="
  vagrant ssh "$dc" -c "
    sudo helm uninstall ldap -n ldap 2>/dev/null || true
    sudo kubectl -n ldap delete pvc --all --wait=false 2>/dev/null || true
    sudo kubectl -n ldap delete secret --all --ignore-not-found 2>/dev/null || true
    sudo kubectl delete ns ldap --wait=false 2>/dev/null || true
  "
done

echo ""
echo "=== cleanup done. Minikube clusters still running. ==="
echo "Re-run install.sh to redeploy, or 'vagrant destroy -f' to nuke the VMs."
