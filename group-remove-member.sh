#!/bin/bash
source "$(dirname "$0")/common.sh"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 groupName user1.name [user2.name ...]"
  echo "Note: groupOfNames requires >=1 member. Removing the last member will fail."
  exit 1
fi

GROUP_NAME="$1"
shift
USERS=("$@")
GROUP_DN="cn=$GROUP_NAME,$GROUPS_OU"

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

if ! ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
     -b "$GROUP_DN" -s base "(objectClass=*)" dn -LLL 2>/dev/null | grep -q "^dn:"; then
  echo "Error: group '$GROUP_NAME' does not exist."
  exit 1
fi

TMP_LDIF=$(make_tmpfile)
{
  echo "dn: $GROUP_DN"
  echo "changetype: modify"
  echo "delete: member"
  for u in "${USERS[@]}"; do
    echo "member: cn=$u,$USERS_OU"
  done
} > "$TMP_LDIF"

ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"
echo "Removed ${#USERS[@]} member(s) from $GROUP_NAME."
