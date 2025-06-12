#!/bin/bash

# === LDAP Configuration Variables ===
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
USERS_OU="ou=users,$BASE_DN"
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,$BASE_DN"

# === Check if pwgen is installed ===
if ! command -v pwgen >/dev/null 2>&1; then
  echo "Error: pwgen is not installed. Install it with: sudo apt install pwgen"
  exit 1
fi

# === Check for required argument ===
if [ -z "$1" ]; then
  echo "Usage: $0 username"
  exit 1
fi

USERNAME="$1"
USER_DN="cn=$USERNAME,$USERS_OU"

# === Generate new password ===
NEW_PASSWORD=$(pwgen -s -y 32 1)

# === Create temporary LDIF to modify password ===
TMP_LDIF=$(mktemp)
cat <<EOF > "$TMP_LDIF"
dn: $USER_DN
changetype: modify
replace: userPassword
userPassword: $NEW_PASSWORD
EOF

# === Apply the change ===
ldapmodify -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -f "$TMP_LDIF"
rm -f "$TMP_LDIF"

# === Output credentials ===
echo "Password changed for user: $USERNAME"
echo "New password: $NEW_PASSWORD"
