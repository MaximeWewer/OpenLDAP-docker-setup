#!/bin/bash
# Assign a specific ppolicy to a user via pwdPolicySubentry.
# Pass --clear to remove the per-user policy (revert to default).
source "$(dirname "$0")/common.sh"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 username policy-name"
  echo "       $0 username --clear"
  exit 1
fi

USERNAME="$1"
POLICY_OR_FLAG="${2:-}"

USER_DN="cn=$USERNAME,$USERS_OU"
if ! user_exists "$USER_DN"; then
  echo "Error: user '$USERNAME' does not exist."
  exit 1
fi

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")
TMP=$(make_tmpfile)

if [ "$POLICY_OR_FLAG" = "--clear" ]; then
  cat <<EOF > "$TMP"
dn: $USER_DN
changetype: modify
delete: pwdPolicySubentry
EOF
  ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP"
  echo "Removed per-user policy from $USERNAME (default policy now applies)."
else
  POLICY_DN="cn=$POLICY_OR_FLAG,ou=policies,$BASE_DN"
  # Verify policy exists
  if ! ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
       -b "$POLICY_DN" -s base "(objectClass=*)" dn -LLL 2>/dev/null | grep -q '^dn:'; then
    echo "Error: policy '$POLICY_OR_FLAG' does not exist at $POLICY_DN."
    echo "Create it first with set-ppolicy.sh."
    exit 1
  fi

  cat <<EOF > "$TMP"
dn: $USER_DN
changetype: modify
replace: pwdPolicySubentry
pwdPolicySubentry: $POLICY_DN
EOF
  ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP"
  echo "Assigned policy '$POLICY_OR_FLAG' to user '$USERNAME'."
fi
