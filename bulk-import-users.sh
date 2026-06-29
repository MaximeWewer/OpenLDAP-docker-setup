#!/bin/bash
# Import users from a CSV. Each row: firstname.lastname[,group][,mail-override]
# Lines starting with # are ignored. Generates a password per user, outputs a CSV.
source "$(dirname "$0")/common.sh"

if [ -z "${1:-}" ]; then
  cat <<EOF
Usage: $0 users.csv [--group=defaultGroup] [--posix]
CSV format (one user per line):
  firstname.lastname
  firstname.lastname,groupName
  firstname.lastname,groupName,custom@mail.example
EOF
  exit 1
fi

CSV_FILE="$1"
shift
[ -f "$CSV_FILE" ] || { echo "File not found: $CSV_FILE"; exit 1; }

DEFAULT_GROUP=""
POSIX_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --group=*) DEFAULT_GROUP="${arg#--group=}" ;;
    --posix)   POSIX_FLAG="--posix" ;;
  esac
done

CREATED=0
FAILED=0
TMP_CSV=$(make_tmpfile)
echo "user,group,mail,password" > "$TMP_CSV"

while IFS=',' read -r username group mail || [ -n "$username" ]; do
  # Skip blank lines and comments
  [[ -z "$username" || "$username" =~ ^[[:space:]]*# ]] && continue
  username="$(echo "$username" | xargs)"
  group="$(echo "${group:-$DEFAULT_GROUP}" | xargs)"
  mail="$(echo "${mail:-}" | xargs)"

  echo "--- Importing $username (group=${group:-none}) ---"
  GROUP_ARG=""
  [ -n "$group" ] && GROUP_ARG="--group=$group"

  if bash "$(dirname "$0")/create-users.sh" "$username" $GROUP_ARG $POSIX_FLAG 2>&1 | tee /tmp/.bulk.$$; then
    pwd=$(grep "^$username," /tmp/.bulk.$$ | head -1 | cut -d, -f2)
    if [ -n "$mail" ]; then
      bash "$(dirname "$0")/modify-user-attribute.sh" "$username" mail "$mail" >/dev/null 2>&1 \
        && echo "  mail overridden -> $mail"
    fi
    echo "$username,${group:-},${mail:-},${pwd:-?}" >> "$TMP_CSV"
    CREATED=$((CREATED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
  rm -f /tmp/.bulk.$$
done < "$CSV_FILE"

echo
echo "=== Summary ==="
echo "Created: $CREATED"
echo "Failed:  $FAILED"
echo
echo "=== Credentials (CSV) ==="
cat "$TMP_CSV"
