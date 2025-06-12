#!/bin/bash

# === LDAP Configuration Variables ===
LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=example,dc=org"
USERS_OU="ou=users,$BASE_DN"
LOCAL_ADMIN="admin"
LOCAL_ADMIN_PASS="adminpassword"
LOCAL_ADMIN_DN="cn=$LOCAL_ADMIN,$BASE_DN"
MAIL_DOMAIN="example.org"
DEFAULT_UID="1000"
DEFAULT_GID="1000"

# === Check if pwgen is installed ===
if ! command -v pwgen >/dev/null 2>&1; then
  echo "Error: pwgen is not installed. Install it with: sudo apt install pwgen"
  exit 1
fi

# === Check if at least one user is provided ===
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 user1.name user2.name ... --group=groupName"
  exit 1
fi

# === Parse arguments: separate users from optional group name ===
GROUP_NAME=""
USER_LIST=()

for arg in "$@"; do
  if [[ "$arg" =~ --group=(.*) ]]; then
    GROUP_NAME="${BASH_REMATCH[1]}"
  else
    USER_LIST+=("$arg")
  fi
done

# === Initialize CSV output ===
CSV_OUTPUT="user,password"

# === Create each user ===
for user in "${USER_LIST[@]}"; do
  echo "Creating user: $user"

  # Split "user.name" into first and last name
  IFS='.' read -r first last <<< "$user"

  # Capitalize first and last name
  cap_first="$(tr '[:lower:]' '[:upper:]' <<< ${first:0:1})${first:1}"
  cap_last="$(tr '[:lower:]' '[:upper:]' <<< ${last:0:1})${last:1}"
  full_name="$cap_first $cap_last"

  # Generate a random password
  PASSWORD=$(pwgen -s -y 32 1)

  # Append to CSV
  CSV_OUTPUT+=$'\n'"$user,$PASSWORD"

  TMP_LDIF=$(mktemp)
  cat <<EOF > "$TMP_LDIF"
dn: cn=$user,$USERS_OU
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: $user
uid: $user
sn: $cap_last
givenName: $cap_first
displayName: $full_name
mail: $user@$MAIL_DOMAIN
uidNumber: $DEFAULT_UID
gidNumber: $DEFAULT_GID
homeDirectory: /home/$user
loginShell: /bin/bash
userPassword: $PASSWORD
EOF

  ldapadd -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -f "$TMP_LDIF"
  rm -f "$TMP_LDIF"

  # Add user to group if specified
  if [ -n "$GROUP_NAME" ]; then
    echo "Adding $user to group $GROUP_NAME..."
    TMP_GRP_LDIF=$(mktemp)
    cat <<EOF > "$TMP_GRP_LDIF"
dn: cn=$GROUP_NAME,ou=groups,$BASE_DN
changetype: modify
add: member
member: cn=$user,$USERS_OU
EOF
    ldapmodify -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "$LOCAL_ADMIN_DN" -w "$LOCAL_ADMIN_PASS" -f "$TMP_GRP_LDIF"
    rm -f "$TMP_GRP_LDIF"
  fi
done

# === Display or export credentials ===
echo "=== User credentials (CSV format) ==="
echo "$CSV_OUTPUT"
# Optional: echo "$CSV_OUTPUT" > users_created.csv
