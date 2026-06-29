#!/bin/bash
# Read cn=accesslog and report on recent bind activity.
# Needs accesslog overlay configured with: olcAccessLogOps: writes bind
source "$(dirname "$0")/common.sh"

SINCE_HOURS=24
TOP_N=20
FILTER_USER=""

for arg in "$@"; do
  case "$arg" in
    --since=*h)  SINCE_HOURS="${arg#--since=}"; SINCE_HOURS="${SINCE_HOURS%h}" ;;
    --top=*)     TOP_N="${arg#--top=}" ;;
    --user=*)    FILTER_USER="${arg#--user=}" ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--since=NNh] [--top=N] [--user=username]
  --since=NNh   look back NN hours (default: 24)
  --top=N       show top N users (default: 20)
  --user=NAME   focus on a single user
EOF
      exit 0 ;;
  esac
done

CUTOFF=$(date -u -d "$SINCE_HOURS hours ago" +%Y%m%d%H%M%SZ 2>/dev/null \
         || date -u -v-${SINCE_HOURS}H +%Y%m%d%H%M%SZ)

CONFIG_PASSFILE=$(make_passfile "$CONFIG_ADMIN_PASS")

# Pull bind entries from accesslog
FILTER="(&(reqType=bind)(reqStart>=$CUTOFF))"
if [ -n "$FILTER_USER" ]; then
  FILTER="(&$FILTER(reqDN=cn=$FILTER_USER,$USERS_OU))"
fi

TMP=$(make_tmpfile)
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "cn=accesslog" "$FILTER" reqDN reqResult reqStart reqAuthzID reqMethod -LLL 2>/dev/null > "$TMP" \
  || { echo "Error: cannot read cn=accesslog (admin or accesslog not configured?)"; exit 1; }

TOTAL=$(grep -c '^reqStart:' "$TMP")
SUCCESS=$(grep '^reqResult:' "$TMP" | grep -c ': 0$')
FAILED=$((TOTAL - SUCCESS))

echo "=== Bind activity (last ${SINCE_HOURS}h, since $CUTOFF) ==="
echo "Total binds: $TOTAL"
echo "Successful : $SUCCESS"
echo "Failed     : $FAILED"
echo

echo "=== Top $TOP_N binders ==="
grep '^reqDN:' "$TMP" | sort | uniq -c | sort -rn | head -"$TOP_N"

echo
echo "=== Failed binds (latest $TOP_N) ==="
# Each entry block: reqDN + reqResult + reqStart. Group them per entry.
awk '
  /^reqDN: /     { dn = substr($0, 8); next }
  /^reqStart: /  { ts = substr($0, 11); next }
  /^reqResult: / { res = substr($0, 12); if (res != "0") print ts" "res" "dn; next }
' "$TMP" | sort -r | head -"$TOP_N"
