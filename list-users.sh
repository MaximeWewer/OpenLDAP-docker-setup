#!/bin/bash
# List users in ou=users. Filters: --group=name, --locked, --posix
source "$(dirname "$0")/common.sh"

GROUP_FILTER=""
LOCKED_FILTER=""
POSIX_FILTER=""
SHOW_ATTRS="cn uid mail displayName memberOf"

for arg in "$@"; do
  case "$arg" in
    --group=*)   GROUP_FILTER="${arg#--group=}" ;;
    --locked)    LOCKED_FILTER="yes" ;;
    --posix)     POSIX_FILTER="yes" ;;
    --full)      SHOW_ATTRS="*" ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--group=NAME] [--locked] [--posix] [--full]
  --group=NAME  only users that are members of cn=NAME,$GROUPS_OU
  --locked      only locked accounts (have pwdAccountLockedTime)
  --posix       only users with objectClass=posixAccount
  --full        show all attributes
EOF
      exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# Build LDAP filter
FILTER="(objectClass=inetOrgPerson)"
[ "$POSIX_FILTER" = "yes" ]  && FILTER="(&$FILTER(objectClass=posixAccount))"
[ "$LOCKED_FILTER" = "yes" ] && FILTER="(&$FILTER(pwdAccountLockedTime=*))"
[ -n "$GROUP_FILTER" ]       && FILTER="(&$FILTER(memberOf=cn=$GROUP_FILTER,$GROUPS_OU))"

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

# shellcheck disable=SC2086
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$USERS_OU" -s one "$FILTER" $SHOW_ATTRS -LLL 2>/dev/null
