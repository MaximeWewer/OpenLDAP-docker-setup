#!/bin/bash
# List groups in ou=groups. Option: --with-members shows member CNs.
source "$(dirname "$0")/common.sh"

WITH_MEMBERS=""
for arg in "$@"; do
  case "$arg" in
    --with-members) WITH_MEMBERS="yes" ;;
    -h|--help) echo "Usage: $0 [--with-members]"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

if [ "$WITH_MEMBERS" = "yes" ]; then
  ATTRS="cn description member"
else
  ATTRS="cn description"
fi

# shellcheck disable=SC2086
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$GROUPS_OU" -s one "(objectClass=groupOfNames)" $ATTRS -LLL 2>/dev/null
