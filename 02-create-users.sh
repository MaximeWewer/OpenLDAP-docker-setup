#!/bin/bash
source "$(dirname "$0")/common.sh"

# === Check if at least one user is provided ===
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 user1.name user2.name ... [--group=groupName] [--posix]"
  exit 1
fi

# === Parse arguments ===
GROUP_NAME=""
USER_LIST=()
POSIX_ENABLED=false

for arg in "$@"; do
  if [[ "$arg" =~ --group=(.*) ]]; then
    GROUP_NAME="${BASH_REMATCH[1]}"
  elif [[ "$arg" == "--posix" ]]; then
    POSIX_ENABLED=true
  else
    validate_username "$arg"
    USER_LIST+=("$arg")
  fi
done

if [ "${#USER_LIST[@]}" -eq 0 ]; then
  echo "Error: No valid usernames provided."
  exit 1
fi

# === POSIX: find next available uidNumber ===
if $POSIX_ENABLED; then
  DEFAULT_GID="1000"
  ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")
  MAX_UID=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
    -b "$USERS_OU" "(uidNumber=*)" uidNumber 2>/dev/null | grep "^uidNumber:" | awk '{print $2}' | sort -n | tail -1)
  NEXT_UID=$((${MAX_UID:-999} + 1))
fi

# === Initialize CSV output ===
CSV_OUTPUT="user,password"

# === Create each user ===
ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

for user in "${USER_LIST[@]}"; do
  echo "Creating user: $user"

  # Split "user.name" into first and last name
  IFS='.' read -r first last <<< "$user"

  # Capitalize first and last name
  cap_first="$(tr '[:lower:]' '[:upper:]' <<< ${first:0:1})${first:1}"
  cap_last="$(tr '[:lower:]' '[:upper:]' <<< ${last:0:1})${last:1}"
  full_name="$cap_first $cap_last"

  # Generate a random password
  PASSWORD=$(generate_password 32)

  # Append to CSV
  CSV_OUTPUT+=$'\n'"$user,$PASSWORD"

  TMP_LDIF=$(make_tmpfile)
  cat <<EOF > "$TMP_LDIF"
dn: cn=$user,$USERS_OU
objectClass: inetOrgPerson
cn: $user
uid: $user
sn: $cap_last
givenName: $cap_first
displayName: $full_name
mail: $user@$MAIL_DOMAIN
userPassword: $PASSWORD
EOF

  if $POSIX_ENABLED; then
    cat <<EOF >> "$TMP_LDIF"
objectClass: posixAccount
objectClass: shadowAccount
uidNumber: $NEXT_UID
gidNumber: $DEFAULT_GID
homeDirectory: /home/$user
loginShell: /bin/bash
EOF
    NEXT_UID=$((NEXT_UID + 1))
  fi

  ldapadd -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_LDIF"

  # Add user to group if specified
  if [ -n "$GROUP_NAME" ]; then
    echo "Adding $user to group $GROUP_NAME..."
    TMP_GRP_LDIF=$(make_tmpfile)
    cat <<EOF > "$TMP_GRP_LDIF"
dn: cn=$GROUP_NAME,$GROUPS_OU
changetype: modify
add: member
member: cn=$user,$USERS_OU
EOF
    ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -f "$TMP_GRP_LDIF"
  fi
done

# === Display credentials ===
echo "=== User credentials (CSV format) ==="
echo "$CSV_OUTPUT"
