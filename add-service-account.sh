#!/bin/bash
source "$(dirname "$0")/common.sh"

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
  echo "Usage: $0 service_account_name --access read|write --subtree subtree_dn"
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

# === Create service account entry ===
PASSWORD=$(generate_password 32)

TMP_LDIF_ACCOUNT=$(make_tmpfile)
cat <<EOF > "$TMP_LDIF_ACCOUNT"
dn: cn=$ACCOUNT_NAME,$SERVICE_OU
objectClass: inetOrgPerson
cn: $ACCOUNT_NAME
sn: $ACCOUNT_NAME
uid: $ACCOUNT_NAME
userPassword: $PASSWORD
EOF

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")
CONFIG_PASSFILE=$(make_passfile "$CONFIG_ADMIN_PASS")

ldapadd -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF_ACCOUNT"

# === Inject access into existing ACL for the target subtree ===
ACCOUNT_DN="cn=$ACCOUNT_NAME,$SERVICE_OU"
NEW_BY_CLAUSE="by dn.exact=\"$ACCOUNT_DN\" $ACCESS_TYPE"

# Fetch all current olcAccess rules
CURRENT_ACLS=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" \
  -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "$OLC_DB_DN" -s base -LLL olcAccess 2>/dev/null)

# Find the ACL index that matches the target subtree
ACL_INDEX=""
ACL_VALUE=""
while IFS= read -r line; do
  if [[ "$line" =~ ^olcAccess:\ \{([0-9]+)\}to\ dn\.subtree=\"$SUBTREE_DN\" ]]; then
    ACL_INDEX="${BASH_REMATCH[1]}"
    ACL_VALUE="$line"
    # Read continuation lines (starting with a space)
    while IFS= read -r next_line; do
      if [[ "$next_line" =~ ^[[:space:]] ]]; then
        ACL_VALUE="$ACL_VALUE"$'\n'"$next_line"
      else
        break
      fi
    done
    break
  fi
done <<< "$CURRENT_ACLS"

TMP_LDIF_ACL=$(make_tmpfile)

if [[ -n "$ACL_INDEX" ]]; then
  # ACL exists for this subtree — inject the new by clause before "by * none"
  MODIFIED_ACL=$(echo "$ACL_VALUE" | sed "s|by \* none|$NEW_BY_CLAUSE by * none|")

  # Remove the "olcAccess: " prefix for the replace value
  CLEAN_OLD=$(echo "$ACL_VALUE" | sed 's/^olcAccess: //')
  CLEAN_NEW=$(echo "$MODIFIED_ACL" | sed 's/^olcAccess: //')

  cat <<EOF > "$TMP_LDIF_ACL"
dn: $OLC_DB_DN
changetype: modify
delete: olcAccess
olcAccess: $CLEAN_OLD
-
add: olcAccess
olcAccess: $CLEAN_NEW
EOF

  echo "Injecting access into existing ACL {$ACL_INDEX}..."
else
  # No existing ACL for this subtree — add a new one
  cat <<EOF > "$TMP_LDIF_ACL"
dn: $OLC_DB_DN
changetype: modify
add: olcAccess
olcAccess: to dn.subtree="$SUBTREE_DN"
  $NEW_BY_CLAUSE
  by * none
EOF

  echo "No existing ACL for $SUBTREE_DN, adding a new one..."
  echo "Warning: Check ACL ordering with ldapsearch to ensure correct evaluation order."
fi

if ! ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" -f "$TMP_LDIF_ACL"; then
  echo "Error: Failed to update ACL. The service account was created but has no access."
  echo "You may need to manually update the ACL."
  exit 1
fi

echo ""
echo "Service account created: $ACCOUNT_NAME"
echo "Password: $PASSWORD"
echo "Access granted: $ACCESS_TYPE on $SUBTREE_DN"
