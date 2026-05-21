#!/bin/bash
source "$(dirname "$0")/common.sh"

# === Argument Check ===
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 groupName member1.name [member2.name ...]"
  echo "At least one member is required (groupOfNames constraint)."
  exit 1
fi

GROUP_NAME="$1"
shift
MEMBERS=("$@")

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

# === Verify all members exist ===
for member in "${MEMBERS[@]}"; do
  MEMBER_DN="cn=$member,$USERS_OU"
  if ! user_exists "$MEMBER_DN"; then
    echo "Error: User '$member' does not exist."
    exit 1
  fi
done

echo "Creating group: $GROUP_NAME"

TMP_LDIF=$(make_tmpfile)

# === LDIF for group creation ===
cat <<EOF > "$TMP_LDIF"
dn: cn=$GROUP_NAME,$GROUPS_OU
objectClass: groupOfNames
cn: $GROUP_NAME
EOF

for member in "${MEMBERS[@]}"; do
  echo "member: cn=$member,$USERS_OU" >> "$TMP_LDIF"
done

# === Apply LDIF to LDAP ===
ldapadd -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"

echo "Group $GROUP_NAME created with ${#MEMBERS[@]} member(s)."
