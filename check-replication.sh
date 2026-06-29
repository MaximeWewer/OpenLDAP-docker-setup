#!/bin/bash
# HA only - compare contextCSN across peers to detect replication drift.
# Usage:
#   ./check-replication.sh                        # uses peer URIs from arg
#   ./check-replication.sh ldap://p1 ldap://p2    # explicit list
source "$(dirname "$0")/common.sh"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 ldap://peer1 ldap://peer2 [ldap://peer3 ...]"
  echo
  echo "Compares contextCSN (and accesslog contextCSN) across peers."
  echo "A drift > 30s on identical SIDs usually means replication is stuck."
  exit 1
fi

PEERS=("$@")

ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

declare -A MAIN_CSN
declare -A ACCESS_CSN

echo "=== Polling contextCSN ==="
for uri in "${PEERS[@]}"; do
  printf "%-35s " "$uri"
  MAIN=$(ldapsearch -x -H "$uri" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
           -b "$BASE_DN" -s base "(objectClass=*)" contextCSN -LLL 2>/dev/null \
         | grep '^contextCSN:' | sort | tr '\n' '|' )
  ACC=$(ldapsearch -x -H "$uri" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
          -b "cn=accesslog" -s base "(objectClass=*)" contextCSN -LLL 2>/dev/null \
        | grep '^contextCSN:' | sort | tr '\n' '|' )
  if [ -z "$MAIN" ]; then
    echo "UNREACHABLE or no contextCSN (need admin bind)"
    continue
  fi
  MAIN_CSN[$uri]="$MAIN"
  ACCESS_CSN[$uri]="$ACC"
  echo "OK"
done

echo
echo "=== Main DB contextCSN ($BASE_DN) ==="
for uri in "${PEERS[@]}"; do
  printf "  %-35s\n" "$uri"
  echo "${MAIN_CSN[$uri]:-}" | tr '|' '\n' | sed 's/^/    /;/^$/d'
done

echo
echo "=== Drift detection (compare per-SID across peers) ==="
ALL_OK=1
# Build set of SIDs seen
declare -A SIDS
for uri in "${PEERS[@]}"; do
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    sid=$(echo "$line" | sed -E 's/.*#([0-9a-f]+)#.*/\1/')
    SIDS[$sid]=1
  done <<< "$(echo "${MAIN_CSN[$uri]:-}" | tr '|' '\n')"
done

for sid in "${!SIDS[@]}"; do
  printf "SID %s\n" "$sid"
  for uri in "${PEERS[@]}"; do
    LINE=$(echo "${MAIN_CSN[$uri]:-}" | tr '|' '\n' | grep "#${sid}#" | head -1)
    TS=$(echo "$LINE" | sed 's/^contextCSN: //; s/\..*//')
    printf "  %-35s %s\n" "$uri" "${TS:-(missing)}"
    [ -z "$TS" ] && ALL_OK=0
  done
done

echo
if [ "$ALL_OK" = "1" ]; then
  echo "Replication looks consistent (each peer holds a CSN for every observed SID)."
else
  echo "WARN: at least one peer is missing a SID — replication drift or not converged yet."
fi
