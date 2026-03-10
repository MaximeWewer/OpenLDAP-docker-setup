#!/bin/bash
source "$(dirname "$0")/common.sh"

# === Check for required argument ===
if [ -z "${1:-}" ]; then
  echo "Usage: $0 username"
  exit 1
fi

USERNAME="$1"
USER_DN="cn=$USERNAME,$USERS_OU"

# === Check user exists ===
if ! user_exists "$USER_DN"; then
  echo "Error: User '$USERNAME' does not exist."
  exit 1
fi

# === Generate new password ===
NEW_PASSWORD=$(generate_password 32)

# === Create temporary LDIF to modify password ===
TMP_LDIF=$(make_tmpfile)
cat <<EOF > "$TMP_LDIF"
dn: $USER_DN
changetype: modify
replace: userPassword
userPassword: $NEW_PASSWORD
EOF

# === Apply the change ===
ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")
ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"

# === Output credentials ===
echo "Password changed for user: $USERNAME"
echo "New password: $NEW_PASSWORD"
