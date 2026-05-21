#!/bin/bash
source "$(dirname "$0")/common.sh"

# === Check argument ===
if [ -z "${1:-}" ]; then
  echo "Usage: $0 service_account_name"
  exit 1
fi

ACCOUNT_NAME="$1"
ACCOUNT_DN="cn=$ACCOUNT_NAME,$SERVICE_OU"

# === Check account exists ===
if ! user_exists "$ACCOUNT_DN"; then
  echo "Error: Service account '$ACCOUNT_NAME' does not exist."
  exit 1
fi

NEW_PASSWORD=$(generate_password 32)

TMP_LDIF=$(make_tmpfile)
cat <<EOF > "$TMP_LDIF"
dn: $ACCOUNT_DN
changetype: modify
replace: userPassword
userPassword: $NEW_PASSWORD
EOF

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")
ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"

echo "Password updated for service account: $ACCOUNT_NAME"
echo "New password: $NEW_PASSWORD"
