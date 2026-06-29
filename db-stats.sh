#!/bin/bash
# Dump back_mdb stats from cn=Monitor + raw file size.
# Use this to spot MDB_MAP_FULL before it bites.
source "$(dirname "$0")/common.sh"

# Path to data/ (per-mode). Auto-detect: ./data or look for known mode dirs.
DATA_PATH=""
for cand in ./data ./standalone/data ./ha-active-active/data ./ha-active-passive/data; do
  if [ -d "$cand" ]; then
    DATA_PATH=$(realpath "$cand")
    break
  fi
done

CONFIG_PASSFILE=$(make_passfile "$CONFIG_ADMIN_PASS")

echo "=== Per-database stats (cn=Monitor) ==="
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "cn=Databases,cn=Monitor" "(objectClass=*)" \
  monitoredInfo monitorCounter namingContexts olmMDBEntries olmMDBPagesMax olmMDBPagesUsed olmMDBPagesFree \
  -LLL 2>/dev/null | grep -E '^(dn:|monitor|naming|olm)' || echo "(back_monitor may not be enabled)"

echo
echo "=== olcDbMaxSize per DB ==="
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "cn=config" "(objectClass=olcMdbConfig)" olcSuffix olcDbMaxSize olcDbDirectory -LLL 2>/dev/null \
  | grep -E '^(dn:|olcSuffix|olcDbMaxSize|olcDbDirectory)'

if [ -n "$DATA_PATH" ]; then
  echo
  echo "=== Physical file size (host: $DATA_PATH) ==="
  for d in "$DATA_PATH"/*/; do
    [ -d "$d" ] || continue
    F="$d/data.mdb"
    [ -f "$F" ] && du -h "$F"
  done
fi
