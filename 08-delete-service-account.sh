#!/bin/bash

# === LDAP Configuration ===
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
SERVICE_OU="ou=service-accounts,$BASE_DN"
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,$BASE_DN"

# === Check argument ===
if [ -z "$1" ]; then
  echo "Usage: $0 service_account_name"
  exit 1
fi

ACCOUNT_NAME="$1"

ldapdelete -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" "cn=$ACCOUNT_NAME,$SERVICE_OU"

echo "Service account deleted: $ACCOUNT_NAME"
