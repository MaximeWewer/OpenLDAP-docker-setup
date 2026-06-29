#!/bin/bash
# Export users to CSV (no passwords - hashes only on request).
source "$(dirname "$0")/common.sh"

OUT="-"
WITH_HASH="no"
for arg in "$@"; do
  case "$arg" in
    --out=*)     OUT="${arg#--out=}" ;;
    --with-hash) WITH_HASH="yes" ;;
    -h|--help)
      echo "Usage: $0 [--out=file.csv] [--with-hash]"
      echo "Default output: stdout (CSV). --with-hash includes userPassword (admin-only)."
      exit 0 ;;
  esac
done

ATTRS="cn uid mail displayName telephoneNumber"
[ "$WITH_HASH" = "yes" ] && ATTRS="$ATTRS userPassword"

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

TMP=$(make_tmpfile)
# shellcheck disable=SC2086
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$USERS_OU" -s one "(objectClass=inetOrgPerson)" $ATTRS -LLL 2>/dev/null > "$TMP"

# Parse LDIF -> CSV via awk
HEADER="uid,cn,mail,displayName,telephoneNumber"
[ "$WITH_HASH" = "yes" ] && HEADER="$HEADER,userPassword"

awk -v with_hash="$WITH_HASH" -v header="$HEADER" '
  BEGIN { print header }
  /^$/ { if (length(uid)>0) print_row(); reset() }
  /^uid: /            { uid = substr($0,6) }
  /^cn: /             { if (cn=="")  cn = substr($0,5) }
  /^mail: /           { mail = substr($0,7) }
  /^displayName: /    { displayName = substr($0,15) }
  /^telephoneNumber: /{ telephoneNumber = substr($0,18) }
  /^userPassword:: /  { userPassword = substr($0,16) }
  END { if (length(uid)>0) print_row() }

  function reset() { uid=""; cn=""; mail=""; displayName=""; telephoneNumber=""; userPassword="" }
  function print_row() {
    row = uid","cn","mail","displayName","telephoneNumber
    if (with_hash == "yes") row = row","userPassword
    print row
  }
' "$TMP" > "$TMP.csv"

if [ "$OUT" = "-" ]; then
  cat "$TMP.csv"
else
  cp "$TMP.csv" "$OUT"
  echo "Exported to $OUT"
fi
