#!/bin/bash

# === LDAP Configuration Variables ===
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
USERS_OU="ou=users,$BASE_DN"
GROUPS_OU="ou=groups,$BASE_DN"
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,$BASE_DN"

# === Argument Check ===
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 groupName [group1 group2 ...]"
  exit 1
fi

GROUP_NAME="$1"
shift
MEMBERS=("$@")

echo "Creating group: $GROUP_NAME"

TMP_LDIF=$(mktemp)

# === LDIF for group creation ===
cat <<EOF > "$TMP_LDIF"
dn: cn=$GROUP_NAME,$GROUPS_OU
objectClass: groupOfNames
cn: $GROUP_NAME
EOF

# === Add initial members (at least one is required for groupOfNames) ===
if [ "${#MEMBERS[@]}" -eq 0 ]; then
  # No members provided → add a dummy DN just to pass schema requirement
  echo "member: cn=dummy,$USERS_OU" >> "$TMP_LDIF"
else
  for member in "${MEMBERS[@]}"; do
    echo "member: cn=$member,$USERS_OU" >> "$TMP_LDIF"
  done
fi

# === Apply LDIF to LDAP ===
ldapadd -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -f "$TMP_LDIF"
rm -f "$TMP_LDIF"

echo "Group $GROUP_NAME created with ${#MEMBERS[@]} member(s)."
