#!/bin/bash
source "$(dirname "$0")/common.sh"

# === Check for at least one user ===
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 user1.name user2.name ..."
  exit 1
fi

USER_LIST=("$@")
ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

for user in "${USER_LIST[@]}"; do
  USER_DN="cn=$user,$USERS_OU"

  # === Check user exists ===
  if ! user_exists "$USER_DN"; then
    echo "Warning: User '$user' does not exist, skipping."
    continue
  fi

  echo "Processing deletion of user: $user"

  # === Fetch groups from memberOf attribute ===
  GROUPS_SEARCH=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
    -b "$USER_DN" memberOf 2>/dev/null | grep 'memberOf:' | awk '{print $2}') || true

  # === Remove the user from each group ===
  for group_dn in $GROUPS_SEARCH; do
    echo "Removing $user from $group_dn..."

    TMP_GRP_LDIF=$(make_tmpfile)
    cat <<EOF > "$TMP_GRP_LDIF"
dn: $group_dn
changetype: modify
delete: member
member: $USER_DN
EOF

    ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_GRP_LDIF" || true
  done

  # === Delete the user entry from LDAP ===
  echo "Deleting LDAP entry: $USER_DN"
  ldapdelete -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" "$USER_DN"
done
