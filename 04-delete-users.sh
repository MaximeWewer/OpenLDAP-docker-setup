#!/bin/bash

# === LDAP Configuration Variables ===
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
USERS_OU="ou=users,$BASE_DN"
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,$BASE_DN"

# === Check for at least one user ===
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 user1.name user2.name ..."
  exit 1
fi

USER_LIST=("$@")

for user in "${USER_LIST[@]}"; do
  echo "Processing deletion of user: $user"
  USER_DN="cn=$user,$USERS_OU"

  # === Fetch groups from memberOf attribute ===
  GROUPS_SEARCH=$(ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -b "$USER_DN" memberOf | grep 'memberOf:' | awk '{print $2}')

  # === Remove the user from each group dynamically ===
  for group_dn in $GROUPS_SEARCH; do
    echo "Removing $user from $group_dn..."

    TMP_GRP_LDIF=$(mktemp)
    cat <<EOF > "$TMP_GRP_LDIF"
dn: $group_dn
changetype: modify
delete: member
member: $USER_DN
EOF

    ldapmodify -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -f "$TMP_GRP_LDIF"
    rm -f "$TMP_GRP_LDIF"
  done

  # === Delete the user entry from LDAP ===
  echo "Deleting LDAP entry: $USER_DN"
  ldapdelete -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" "$USER_DN"
done
