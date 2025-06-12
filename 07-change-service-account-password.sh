#!/bin/bash

# === LDAP Configuration ===
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
SERVICE_OU="ou=service-accounts,$BASE_DN"
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,$BASE_DN"

# === Check if pwgen is installed ===
if ! command -v pwgen >/dev/null 2>&1; then
  echo "Error: pwgen is not installed. Install it with: sudo apt install pwgen"
  exit 1
fi

# === Check argument ===
if [ -z "$1" ]; then
  echo "Usage: $0 service_account_name"
  exit 1
fi

ACCOUNT_NAME="$1"
NEW_PASSWORD=$(pwgen -s -y 32 1)

TMP_LDIF=$(mktemp)
cat <<EOF > "$TMP_LDIF"
dn: cn=$ACCOUNT_NAME,$SERVICE_OU
changetype: modify
replace: userPassword
userPassword: $NEW_PASSWORD
EOF

ldapmodify -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -f "$TMP_LDIF"
rm -f "$TMP_LDIF"

echo "Password updated for service account: $ACCOUNT_NAME"
echo "New password: $NEW_PASSWORD"
