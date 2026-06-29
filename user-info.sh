#!/bin/bash
# Full snapshot of a user: identity, groups, ppolicy state, derived status.
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

echo "=== Identity ==="
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$USER_DN" -s base "(objectClass=*)" \
  cn uid mail givenName sn displayName telephoneNumber \
  uidNumber gidNumber homeDirectory loginShell \
  -LLL 2>/dev/null | grep -v '^$'

echo
echo "=== Group memberships (memberOf) ==="
MEMBEROF=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$USER_DN" -s base "(objectClass=*)" memberOf -LLL 2>/dev/null | grep '^memberOf:' | sed 's/^memberOf: //')
if [ -z "$MEMBEROF" ]; then
  echo "(none)"
else
  echo "$MEMBEROF"
fi

echo
echo "=== ppolicy state ==="
PPOL=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$USER_DN" -s base "(objectClass=*)" \
  pwdChangedTime pwdFailureTime pwdAccountLockedTime pwdReset pwdPolicySubentry \
  -LLL 2>/dev/null | grep -E '^pwd')
if [ -z "$PPOL" ]; then
  echo "(no ppolicy attributes — never authenticated, or no policy applied yet)"
else
  echo "$PPOL"
fi

echo
echo "=== Derived status ==="
if echo "$PPOL" | grep -q '^pwdAccountLockedTime:'; then
  echo "  LOCKED  — use unlock-user.sh $USERNAME"
elif echo "$PPOL" | grep -q '^pwdReset: TRUE'; then
  echo "  RESET REQUIRED — user must change password at next login"
else
  echo "  active"
fi
FAILS=$(echo "$PPOL" | grep -c '^pwdFailureTime:')
[ "$FAILS" -gt 0 ] && echo "  recent failed bind attempts: $FAILS"
