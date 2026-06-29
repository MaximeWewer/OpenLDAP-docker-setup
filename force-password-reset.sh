#!/bin/bash
# Force a user to change their password at next bind.
# Sets pwdReset: TRUE - Self Service Password reads it and forces a change.
source "$(dirname "$0")/common.sh"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 username"
  exit 1
fi

USERNAME="$1"
USER_DN="cn=$USERNAME,$USERS_OU"

if ! user_exists "$USER_DN"; then
  echo "Error: user '$USERNAME' does not exist."
  exit 1
fi

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

TMP_LDIF=$(make_tmpfile)
cat <<EOF > "$TMP_LDIF"
dn: $USER_DN
changetype: modify
replace: pwdReset
pwdReset: TRUE
EOF

ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"
echo "User '$USERNAME' will be forced to change password at next login (pwdReset: TRUE)."
