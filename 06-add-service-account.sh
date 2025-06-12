#!/bin/bash

# === LDAP Configuration ===
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
SERVICE_OU="ou=service-accounts,$BASE_DN"
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,$BASE_DN"
CONFIG_ADMIN="cn=adminconfig,cn=config"
CONFIG_ADMIN_PASS="adminpasswordconfig"
OLC_DB_DN="olcDatabase={2}mdb,cn=config"

# === Check if pwgen is installed ===
if ! command -v pwgen >/dev/null 2>&1; then
  echo "Error: pwgen is not installed. Install it with: sudo apt install pwgen"
  exit 1
fi

# === Parse arguments ===
ACCOUNT_NAME=""
ACCESS_TYPE="read"
SUBTREE_DN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --access)
      ACCESS_TYPE="$2"
      shift 2
      ;;
    --subtree)
      SUBTREE_DN="$2"
      shift 2
      ;;
    *)
      if [[ -z "$ACCOUNT_NAME" ]]; then
        ACCOUNT_NAME="$1"
        shift
      else
        echo "Unknown argument: $1"
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$ACCOUNT_NAME" ]]; then
  echo "Usage: $0 service_account_name [--access read|write] [--subtree subtree_dn]"
  exit 1
fi

if [[ "$ACCESS_TYPE" != "read" && "$ACCESS_TYPE" != "write" ]]; then
  echo "Error: --access must be 'read' or 'write'"
  exit 1
fi

if [[ -z "$SUBTREE_DN" ]]; then
  echo "Error: --subtree must be specified"
  exit 1
fi

# === Create service account ===
PASSWORD=$(pwgen -s -y 32 1)

# Create a temporary LDIF file for the new service account
TMP_LDIF_ACCOUNT=$(mktemp)
cat <<EOF > "$TMP_LDIF_ACCOUNT"
dn: cn=$ACCOUNT_NAME,$SERVICE_OU
objectClass: inetOrgPerson
cn: $ACCOUNT_NAME
sn: $ACCOUNT_NAME
uid: $ACCOUNT_NAME
userPassword: $PASSWORD
EOF

# Add the new service account to the LDAP directory
ldapadd -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -f "$TMP_LDIF_ACCOUNT"
rm -f "$TMP_LDIF_ACCOUNT"

# === Inject olcAccess for this account ===
TMP_LDIF_ACL=$(mktemp)
ACCOUNT_DN="cn=$ACCOUNT_NAME,$SERVICE_OU"
OLC_ACCESS_ENTRY="by dn.exact=\"$ACCOUNT_DN\" $ACCESS_TYPE"

cat <<EOF > "$TMP_LDIF_ACL"
dn: $OLC_DB_DN
changetype: modify
add: olcAccess
olcAccess: to dn.subtree="$SUBTREE_DN"
  $OLC_ACCESS_ENTRY
  by * none
EOF

# Apply the new ACL
ldapmodify -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$CONFIG_ADMIN" -w "$CONFIG_ADMIN_PASS" -f "$TMP_LDIF_ACL"
rm -f "$TMP_LDIF_ACL"

echo "Service account created: $ACCOUNT_NAME"
echo "Password: $PASSWORD"
echo "Access granted: $ACCESS_TYPE on $SUBTREE_DN"
