#!/bin/bash
source "$(dirname "$0")/common.sh"

# === Check argument ===
if [ -z "${1:-}" ]; then
  echo "Usage: $0 service_account_name"
  exit 1
fi

ACCOUNT_NAME="$1"
ACCOUNT_DN="cn=$ACCOUNT_NAME,$SERVICE_OU"

# === Check account exists ===
if ! user_exists "$ACCOUNT_DN"; then
  echo "Error: Service account '$ACCOUNT_NAME' does not exist."
  exit 1
fi

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")
CONFIG_PASSFILE=$(make_passfile "$CONFIG_ADMIN_PASS")

# === Remove service account references from ACLs ===
echo "Checking ACLs for references to $ACCOUNT_DN..."

CURRENT_ACLS=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" \
  -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "$OLC_DB_DN" -s base -LLL olcAccess 2>/dev/null)

# Parse ACLs into an array
ACLS_MODIFIED=0
declare -a ACL_ENTRIES=()
CURRENT_ENTRY=""

while IFS= read -r line; do
  if [[ "$line" =~ ^olcAccess:\ (.*)$ ]]; then
    if [[ -n "$CURRENT_ENTRY" ]]; then
      ACL_ENTRIES+=("$CURRENT_ENTRY")
    fi
    CURRENT_ENTRY="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^[[:space:]] && -n "$CURRENT_ENTRY" ]]; then
    CURRENT_ENTRY="$CURRENT_ENTRY"$'\n'"$line"
  else
    if [[ -n "$CURRENT_ENTRY" ]]; then
      ACL_ENTRIES+=("$CURRENT_ENTRY")
      CURRENT_ENTRY=""
    fi
  fi
done <<< "$CURRENT_ACLS"
if [[ -n "$CURRENT_ENTRY" ]]; then
  ACL_ENTRIES+=("$CURRENT_ENTRY")
fi

# Check each ACL for references to this service account
for acl in "${ACL_ENTRIES[@]}"; do
  if echo "$acl" | grep -q "dn.exact=\"$ACCOUNT_DN\""; then
    echo "Found reference in ACL, removing..."

    # Remove the clause containing this account's access
    MODIFIED_ACL=$(echo "$acl" | sed "s| by dn.exact=\"$ACCOUNT_DN\" [a-z]*||g")

    TMP_LDIF=$(make_tmpfile)
    cat <<EOF > "$TMP_LDIF"
dn: $OLC_DB_DN
changetype: modify
delete: olcAccess
olcAccess: $acl
-
add: olcAccess
olcAccess: $MODIFIED_ACL
EOF

    if ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" -f "$TMP_LDIF"; then
      echo "ACL cleaned up successfully."
      ACLS_MODIFIED=$((ACLS_MODIFIED + 1))
    else
      echo "Warning: Failed to update ACL. You may need to manually remove the reference."
    fi
  fi
done

if [[ $ACLS_MODIFIED -eq 0 ]]; then
  echo "No ACL references found for this service account."
fi

# === Delete the service account entry ===
ldapdelete -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" "$ACCOUNT_DN"
echo "Service account deleted: $ACCOUNT_NAME"
