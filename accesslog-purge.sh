#!/bin/bash
# Force an immediate purge of cn=accesslog older than --keep-hours.
# Works by temporarily tightening olcAccessLogPurge to trigger an inline purge,
# then restoring the original setting. No restart.
source "$(dirname "$0")/common.sh"

KEEP_HOURS=24
RESTORE_PURGE="07+00:00 01+00:00"
DRY_RUN="no"

for arg in "$@"; do
  case "$arg" in
    --keep-hours=*) KEEP_HOURS="${arg#--keep-hours=}" ;;
    --restore-purge=*) RESTORE_PURGE="${arg#--restore-purge=}" ;;
    --dry-run) DRY_RUN="yes" ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--keep-hours=N] [--restore-purge="DD+HH:MM HH+MM"] [--dry-run]
  --keep-hours=N        keep entries newer than N hours (default: 24)
  --restore-purge=...   olcAccessLogPurge value to restore after force-purge
                        (default: $RESTORE_PURGE)
  --dry-run             just count entries that would be purged

Note: MDB does not shrink data.mdb file after delete - it only reuses freed
pages. For physical disk reclaim see "Reclaiming disk space" in root README.
EOF
      exit 0 ;;
  esac
done

# Convert keep-hours to "DD+HH:MM" - keep modulo days+hours
DAYS=$(( KEEP_HOURS / 24 ))
REM_H=$(( KEEP_HOURS % 24 ))
TIGHT_KEEP=$(printf '%02d+%02d:00' "$DAYS" "$REM_H")

CONFIG_PASSFILE=$(make_passfile "$CONFIG_ADMIN_PASS")

echo "=== Current accesslog config ==="
OVL_DN=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "cn=config" "(olcOverlay=accesslog)" dn -LLL 2>/dev/null | grep '^dn:' | head -1 | sed 's/^dn: //')
if [ -z "$OVL_DN" ]; then
  echo "Error: accesslog overlay not found in cn=config" >&2
  exit 1
fi
echo "Overlay DN: $OVL_DN"

ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "$OVL_DN" -s base "(objectClass=*)" olcAccessLogPurge -LLL 2>/dev/null | grep -i purge

if [ "$DRY_RUN" = "yes" ]; then
  # Count entries older than KEEP_HOURS
  CUTOFF=$(date -u -d "$KEEP_HOURS hours ago" +%Y%m%d%H%M%SZ 2>/dev/null \
           || date -u -v-${KEEP_HOURS}H +%Y%m%d%H%M%SZ)
  echo
  echo "Cutoff (UTC): $CUTOFF"
  COUNT=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
            -b "cn=accesslog" "(&(objectClass=auditObject)(reqStart<=$CUTOFF))" dn -LLL 2>/dev/null \
          | grep -c '^dn:')
  echo "Entries older than ${KEEP_HOURS}h: $COUNT"
  exit 0
fi

# Step 1: tighten purge -> "keep TIGHT_KEEP, purge every 5m"
echo
echo "=== Triggering inline purge (keep ${TIGHT_KEEP}, sweep every 00+00:05) ==="
TMP1=$(make_tmpfile)
cat <<EOF > "$TMP1"
dn: $OVL_DN
changetype: modify
replace: olcAccessLogPurge
olcAccessLogPurge: $TIGHT_KEEP 00+00:05
EOF
ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" -f "$TMP1"

echo "Waiting 10 minutes for the purge cycle to complete..."
# Sleep is intentionally long enough for the sweep cycle (5m) + safety margin.
# OpenLDAP runs the purge on the configured cron interval; the first sweep
# happens at most "sweep interval" after the config change.
sleep 600

# Step 2: restore original purge interval
echo
echo "=== Restoring purge config: $RESTORE_PURGE ==="
TMP2=$(make_tmpfile)
cat <<EOF > "$TMP2"
dn: $OVL_DN
changetype: modify
replace: olcAccessLogPurge
olcAccessLogPurge: $RESTORE_PURGE
EOF
ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" -f "$TMP2"

echo "Done. Use db-stats.sh to verify the new size."
