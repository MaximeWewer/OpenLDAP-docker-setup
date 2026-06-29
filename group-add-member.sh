#!/bin/bash
source "$(dirname "$0")/common.sh"

# === Argument check ===
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 groupName user1.name [user2.name ...]"
  exit 1
fi

GROUP_NAME="$1"
shift
USERS=("$@")
GROUP_DN="cn=$GROUP_NAME,$GROUPS_OU"

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

# === Group exists ===
if ! ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
     -b "$GROUP_DN" -s base "(objectClass=*)" dn -LLL 2>/dev/null | grep -q "^dn:"; then
  echo "Error: group '$GROUP_NAME' does not exist."
  exit 1
fi

# === Add each user ===
TMP_LDIF=$(make_tmpfile)
{
  echo "dn: $GROUP_DN"
  echo "changetype: modify"
  echo "add: member"
  for u in "${USERS[@]}"; do
    USER_DN="cn=$u,$USERS_OU"
    if ! user_exists "$USER_DN"; then
      echo "Error: user '$u' does not exist." >&2
      exit 1
    fi
    echo "member: $USER_DN"
  done
} > "$TMP_LDIF"

ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"
echo "Added ${#USERS[@]} member(s) to $GROUP_NAME."
