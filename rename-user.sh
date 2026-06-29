#!/bin/bash
# Rename a user: cn=old.name -> cn=new.name. Also updates uid, sn, givenName,
# displayName, mail. Group memberships migrate automatically (refint overlay).
source "$(dirname "$0")/common.sh"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 old.name new.name"
  exit 1
fi

OLD_NAME="$1"
NEW_NAME="$2"

validate_username "$OLD_NAME"
validate_username "$NEW_NAME"

OLD_DN="cn=$OLD_NAME,$USERS_OU"
NEW_DN="cn=$NEW_NAME,$USERS_OU"

if ! user_exists "$OLD_DN"; then
  echo "Error: source user '$OLD_NAME' does not exist."
  exit 1
fi
if user_exists "$NEW_DN"; then
  echo "Error: target user '$NEW_NAME' already exists."
  exit 1
fi

IFS='.' read -r FIRST LAST <<< "$NEW_NAME"
CAP_FIRST="$(tr '[:lower:]' '[:upper:]' <<< ${FIRST:0:1})${FIRST:1}"
CAP_LAST="$(tr '[:lower:]' '[:upper:]' <<< ${LAST:0:1})${LAST:1}"
DISPLAY="$CAP_FIRST $CAP_LAST"

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

# Step 1: rename DN (modrdn). refint overlay propagates the change into group member values.
echo "=== Renaming DN: $OLD_DN -> $NEW_DN ==="
TMP_RDN=$(make_tmpfile)
cat <<EOF > "$TMP_RDN"
dn: $OLD_DN
changetype: modrdn
newrdn: cn=$NEW_NAME
deleteoldrdn: 1
EOF
ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_RDN"

# Step 2: refresh derived attributes
echo "=== Updating uid/mail/displayName/sn/givenName ==="
TMP_MOD=$(make_tmpfile)
cat <<EOF > "$TMP_MOD"
dn: $NEW_DN
changetype: modify
replace: uid
uid: $NEW_NAME
-
replace: sn
sn: $CAP_LAST
-
replace: givenName
givenName: $CAP_FIRST
-
replace: displayName
displayName: $DISPLAY
-
replace: mail
mail: $NEW_NAME@$MAIL_DOMAIN
EOF
ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_MOD"

echo "Renamed $OLD_NAME -> $NEW_NAME"
