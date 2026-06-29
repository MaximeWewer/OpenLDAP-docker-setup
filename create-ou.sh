#!/bin/bash
# Create an OU under the base DN.
source "$(dirname "$0")/common.sh"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 ou-name [--parent=PARENT_DN] [--description=TEXT]"
  echo "  Default parent: $BASE_DN"
  exit 1
fi

OU_NAME="$1"
shift
PARENT_DN="$BASE_DN"
DESC=""

for arg in "$@"; do
  case "$arg" in
    --parent=*)      PARENT_DN="${arg#--parent=}" ;;
    --description=*) DESC="${arg#--description=}" ;;
  esac
done

OU_DN="ou=$OU_NAME,$PARENT_DN"
ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

TMP=$(make_tmpfile)
{
  echo "dn: $OU_DN"
  echo "objectClass: organizationalUnit"
  echo "ou: $OU_NAME"
  [ -n "$DESC" ] && echo "description: $DESC"
} > "$TMP"

ldapadd -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP"
echo "Created $OU_DN"
