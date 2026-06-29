#!/bin/bash
# Reset ppolicy lockout + failure counters on a user.
# Clears: pwdAccountLockedTime, pwdFailureTime
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

# Show current state
echo "=== Current ppolicy state ==="
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$USER_DN" -s base "(objectClass=*)" \
  pwdAccountLockedTime pwdFailureTime pwdChangedTime pwdReset 2>/dev/null \
  | grep -E '^(pwdAccountLockedTime|pwdFailureTime|pwdChangedTime|pwdReset):' \
  || echo "(no ppolicy attributes set — account is not locked)"

TMP_LDIF=$(make_tmpfile)
cat <<EOF > "$TMP_LDIF"
dn: $USER_DN
changetype: modify
delete: pwdAccountLockedTime
-
delete: pwdFailureTime
EOF

echo
echo "=== Unlocking $USER_DN ==="
# Ignore errors if attributes were already absent (ldap result 16 - no such attribute)
ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF" 2>&1 | \
  grep -v 'No such attribute' || true

echo "User '$USERNAME' unlocked."
