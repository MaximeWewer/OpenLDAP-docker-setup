#!/bin/bash
# Modify a single attribute on a user. Supports add/replace/delete.
source "$(dirname "$0")/common.sh"

usage() {
  cat <<EOF
Usage: $0 username attribute value [--op=replace|add|delete]
       $0 username attribute --delete-all      # remove all values of an attribute

Examples:
  $0 john.doe mail john.doe@example.org
  $0 john.doe telephoneNumber "+33 1 23 45 67 89"
  $0 john.doe memberOf cn=admin,ou=groups,$BASE_DN --op=add
  $0 john.doe description --delete-all
EOF
  exit 1
}

[ "$#" -ge 2 ] || usage

USERNAME="$1"
ATTR="$2"
VALUE="${3:-}"
OP="replace"
DELETE_ALL="no"

for arg in "${@:3}"; do
  case "$arg" in
    --op=replace|--op=add|--op=delete) OP="${arg#--op=}" ;;
    --delete-all) DELETE_ALL="yes" ;;
  esac
done

USER_DN="cn=$USERNAME,$USERS_OU"
if ! user_exists "$USER_DN"; then
  echo "Error: user '$USERNAME' does not exist." >&2
  exit 1
fi

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")
TMP_LDIF=$(make_tmpfile)

if [ "$DELETE_ALL" = "yes" ]; then
  cat <<EOF > "$TMP_LDIF"
dn: $USER_DN
changetype: modify
delete: $ATTR
EOF
else
  [ -n "$VALUE" ] || { echo "Error: missing value (or use --delete-all)"; usage; }
  cat <<EOF > "$TMP_LDIF"
dn: $USER_DN
changetype: modify
$OP: $ATTR
$ATTR: $VALUE
EOF
fi

ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"
echo "Modified $USER_DN: $OP $ATTR"
