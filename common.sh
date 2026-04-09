#!/bin/bash
# === Shared configuration for all scripts ===
# Source this file: source "$(dirname "$0")/common.sh"

set -euo pipefail

# LDAP connection
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
USERS_OU="ou=users,$BASE_DN"
GROUPS_OU="ou=groups,$BASE_DN"
SERVICE_OU="ou=service-accounts,$BASE_DN"

# Admin user (subject to ACLs, not rootDN)
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,ou=users,$BASE_DN"

# Config admin (cn=config)
CONFIG_ADMIN="cn=adminconfig,cn=config"
CONFIG_ADMIN_PASS="adminpasswordconfig"
OLC_DB_DN="olcDatabase={1}mdb,cn=config"

# Mail domain for user creation
MAIL_DOMAIN="example.org"

# Image
OPENLDAP_IMAGE="cleanstart/openldap:2.6.13"
LDAP_UID=101
LDAP_GID=102

# === Helper: generate a safe password (LDIF-compatible) ===
# Requires pwgen. Excludes characters that break LDIF parsing.
generate_password() {
  local length="${1:-32}"
  if ! command -v pwgen >/dev/null 2>&1; then
    echo "Error: pwgen is not installed. Install it with: sudo apt install pwgen" >&2
    exit 1
  fi
  # -r excludes: # (LDIF comment), < > (special), space, backslash, single/double quotes
  pwgen -s -y -r '#<>\ "'"'" "$length" 1
}

# === Helper: cleanup temp files on exit ===
_COMMON_TMPFILES=()
register_tmpfile() {
  _COMMON_TMPFILES+=("$1")
}
_cleanup_tmpfiles() {
  for f in "${_COMMON_TMPFILES[@]:-}"; do
    rm -rf "$f"
  done
}
trap _cleanup_tmpfiles EXIT

# === Helper: create a temp file and register it for cleanup ===
make_tmpfile() {
  local f
  f=$(mktemp)
  register_tmpfile "$f"
  echo "$f"
}

# === Helper: write password to a temp file for ldap -y flag ===
# Returns the path to the temp file
make_passfile() {
  local pass="$1"
  local f
  f=$(make_tmpfile)
  printf '%s' "$pass" > "$f"
  chmod 600 "$f"
  echo "$f"
}

# === Helper: check user exists ===
user_exists() {
  local user_dn="$1"
  local passfile
  passfile=$(make_passfile "$LOCAL_ADMIN_PASS")
  ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$passfile" \
    -b "$user_dn" -s base "(objectClass=*)" dn -LLL 2>/dev/null | grep -q "^dn:"
}

# === Helper: validate firstname.lastname format ===
validate_username() {
  local username="$1"
  if [[ ! "$username" =~ ^[a-zA-Z]+\.[a-zA-Z]+$ ]]; then
    echo "Error: Username '$username' must follow the firstname.lastname pattern (e.g. john.doe)" >&2
    return 1
  fi
}
