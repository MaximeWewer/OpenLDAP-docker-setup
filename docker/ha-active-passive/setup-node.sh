#!/bin/bash
# Per-node bootstrap for ACTIVE-PASSIVE (MirrorMode).
# SERVER_ID 1+2 are masters (HAProxy active/backup). SERVER_ID >=3 are read-only consumers.
#
# Usage: ./setup-node.sh [--reset]
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "Error: .env missing. Copy .env.example and edit." >&2
  exit 1
fi
# shellcheck disable=SC1091
set -a; source .env; set +a

: "${SERVER_ID:?SERVER_ID required}"
: "${NODE_URIS:?NODE_URIS required}"
: "${REPLICATOR_DN:?REPLICATOR_DN required}"
: "${REPLICATOR_PASSWORD:?REPLICATOR_PASSWORD required}"
: "${HAPROXY_STATS_USER:=admin}"
: "${HAPROXY_STATS_PASSWORD:=admin}"

IMAGE="cleanstart/openldap:2.6.13"
LDAP_UID=101
LDAP_GID=102

IFS=',' read -r -a PEERS <<< "$NODE_URIS"
NUM_PEERS=${#PEERS[@]}

if [ "$SERVER_ID" -lt 1 ] || [ "$SERVER_ID" -gt "$NUM_PEERS" ]; then
  echo "Error: SERVER_ID=$SERVER_ID out of range (1..$NUM_PEERS)" >&2
  exit 1
fi
if [ "$NUM_PEERS" -lt 2 ]; then
  echo "Error: active-passive needs >=2 peers (1 active + 1 backup)" >&2
  exit 1
fi

if [ "$SERVER_ID" -le 2 ]; then ROLE="master"; else ROLE="consumer"; fi

echo "=== Active-Passive node config ==="
echo "  ServerID:   $SERVER_ID / $NUM_PEERS"
echo "  Role:       $ROLE"
echo "  Peers:      $NODE_URIS"

# === Reset check ===
SLAPD_DIR="./data/slapd.d"
if [ -d "$SLAPD_DIR" ] && [ "$(ls -A $SLAPD_DIR 2>/dev/null)" ]; then
  if [ "${1:-}" = "--reset" ]; then
    echo "Resetting state..."
    docker compose --profile ui down 2>/dev/null || true
    docker run --rm -v "$(pwd)/data:/data" alpine:latest sh -c "rm -rf /data/slapd.d/* /data/openldap-data/* /data/accesslog-data/*"
  else
    echo "Error: $SLAPD_DIR already populated. Run with --reset to wipe." >&2
    exit 1
  fi
fi

mkdir -p ./data/slapd.d ./data/openldap-data ./data/accesslog-data

# === Hash replicator password ===
REPLICATOR_PASSWORD_HASH=$(docker run --rm --entrypoint slappasswd "$IMAGE" -s "$REPLICATOR_PASSWORD")

# === serverID only on masters ===
SERVER_IDS_BLOCK=""
if [ "$ROLE" = "master" ]; then
  SERVER_IDS_BLOCK="olcServerID: $SERVER_ID"
fi

build_syncrepl_entry() {
  local rid="$1" provider="$2"
  printf 'olcSyncRepl: rid=%03d provider=%s\n' "$rid" "$provider"
  printf '  bindmethod=simple binddn="%s"\n' "$REPLICATOR_DN"
  printf '  credentials="%s"\n' "$REPLICATOR_PASSWORD"
  printf '  searchbase="dc=example,dc=org"\n'
  printf '  type=refreshAndPersist retry="5 60 60 +"\n'
  printf '  timeout=1 schemachecking=on\n'
  printf '  logbase="cn=accesslog"\n'
  printf '  logfilter="(&(objectClass=auditWriteObject)(reqResult=0))"\n'
  printf '  syncdata=accesslog\n'
}

MDB_SYNCREPL_BLOCK=""
MDB_MIRRORMODE_LINE=""

if [ "$ROLE" = "master" ]; then
  # Masters replicate from both masters (incl self, filtered by serverID)
  for IDX in 1 2; do
    MDB_SYNCREPL_BLOCK+="$(build_syncrepl_entry "$IDX" "${PEERS[$((IDX-1))]}")"$'\n'
  done
  MDB_MIRRORMODE_LINE="olcMirrorMode: TRUE"
else
  # Consumer: pull from both masters for resilience (no mirrormode -> read-only)
  for IDX in 1 2; do
    MDB_SYNCREPL_BLOCK+="$(build_syncrepl_entry "$IDX" "${PEERS[$((IDX-1))]}")"$'\n'
  done
  MDB_MIRRORMODE_LINE=""
fi
MDB_SYNCREPL_BLOCK="${MDB_SYNCREPL_BLOCK%$'\n'}"

# === Render slapd-config.ldif ===
echo "=== Rendering slapd-config.ldif ==="
TMP_CFG=$(mktemp)
TMP_DATA=$(mktemp -d)
cleanup() { rm -f "$TMP_CFG"; rm -rf "$TMP_DATA"; }
trap cleanup EXIT

export SERVER_IDS_BLOCK MDB_SYNCREPL_BLOCK MDB_MIRRORMODE_LINE REPLICATOR_DN
python3 - > "$TMP_CFG" <<'PYEOF'
import os
with open("init-config/slapd-config.ldif.tmpl") as f: tpl=f.read()
tpl = tpl.replace("@@SERVER_IDS@@",     os.environ.get("SERVER_IDS_BLOCK", ""))
tpl = tpl.replace("@@MDB_SYNCREPL@@",   os.environ.get("MDB_SYNCREPL_BLOCK", ""))
tpl = tpl.replace("@@MDB_MIRRORMODE@@", os.environ.get("MDB_MIRRORMODE_LINE", ""))
tpl = tpl.replace("@@REPLICATOR_DN@@",  os.environ["REPLICATOR_DN"])
print(tpl)
PYEOF

# === Bootstrap cn=config ===
echo "=== Bootstrapping cn=config ==="
docker run --rm --user root \
  -v "$(pwd)/data/slapd.d:/etc/openldap/slapd.d" \
  -v "$(pwd)/data/openldap-data:/var/lib/openldap/openldap-data" \
  -v "$(pwd)/data/accesslog-data:/var/lib/openldap/accesslog-data" \
  -v "$TMP_CFG:/init/slapd-config.ldif:ro" \
  --entrypoint slapadd "$IMAGE" \
  -n 0 -F /etc/openldap/slapd.d -l /init/slapd-config.ldif

# === Load initial data (SERVER_ID=1 only) ===
if [ "$SERVER_ID" = "1" ]; then
  echo "=== Loading base data (node 1 - peers will sync from here) ==="
  awk -v h="$REPLICATOR_PASSWORD_HASH" '
    /^userPassword:/ { print "userPassword: " h; next }
    { print }
  ' ./init-ldifs/replicator.ldif > "$TMP_DATA/replicator-hashed.ldif"

  {
    for ldif in \
      ../base-ldifs/01-base.ldif \
      ../base-ldifs/02-org-ou.ldif \
      ../base-ldifs/03-users.ldif \
      ../base-ldifs/04-service-accounts.ldif \
      ../base-ldifs/05-groups.ldif \
      ../base-ldifs/06-default-ppolicy.ldif \
      "$TMP_DATA/replicator-hashed.ldif"; do
      sed 's/\r$//' "$ldif"
      echo ""; echo ""
    done
  } > "$TMP_DATA/all-data.ldif"

  docker run --rm --user root \
    -v "$(pwd)/data/slapd.d:/etc/openldap/slapd.d" \
    -v "$(pwd)/data/openldap-data:/var/lib/openldap/openldap-data" \
    -v "$(pwd)/data/accesslog-data:/var/lib/openldap/accesslog-data" \
    -v "$TMP_DATA:/init-data:ro" \
    --entrypoint slapadd "$IMAGE" \
    -n 1 -F /etc/openldap/slapd.d -l /init-data/all-data.ldif
else
  echo "=== SERVER_ID=$SERVER_ID: skipping data load (will sync from peers) ==="
fi

# === Fix permissions ===
docker run --rm --user root \
  -v "$(pwd)/data/slapd.d:/etc/openldap/slapd.d" \
  -v "$(pwd)/data/openldap-data:/var/lib/openldap/openldap-data" \
  -v "$(pwd)/data/accesslog-data:/var/lib/openldap/accesslog-data" \
  alpine:latest sh -c "chown -R ${LDAP_UID}:${LDAP_GID} /etc/openldap/slapd.d /var/lib/openldap/openldap-data /var/lib/openldap/accesslog-data"

# === Render haproxy.cfg (balance first: node1 active, node2+ backup) ===
echo "=== Rendering haproxy.cfg (active/backup LB) ==="
LDAP_SERVERS=""; LDAPS_SERVERS=""; IDX=0
for uri in "${PEERS[@]}"; do
  IDX=$((IDX + 1))
  HOSTPORT="${uri#ldap://}"
  HOST="${HOSTPORT%:*}"
  BACKUP_FLAG=""
  [ "$IDX" -gt 1 ] && BACKUP_FLAG=" backup"
  LDAP_SERVERS+="    server node${IDX} ${HOST}:389 check inter 5s rise 2 fall 3${BACKUP_FLAG}"$'\n'
  LDAPS_SERVERS+="    server node${IDX}_s ${HOST}:636 check inter 5s rise 2 fall 3${BACKUP_FLAG}"$'\n'
done
LDAP_SERVERS="${LDAP_SERVERS%$'\n'}"
LDAPS_SERVERS="${LDAPS_SERVERS%$'\n'}"

export LDAP_SERVERS LDAPS_SERVERS HAPROXY_STATS_USER HAPROXY_STATS_PASSWORD
python3 - > haproxy/haproxy.cfg <<'PYEOF'
import os
with open("haproxy/haproxy.cfg.tmpl") as f: tpl=f.read()
for k in ("HAPROXY_STATS_USER","HAPROXY_STATS_PASSWORD","LDAP_SERVERS","LDAPS_SERVERS"):
    tpl=tpl.replace(f"@@{k}@@", os.environ.get(k,""))
print(tpl)
PYEOF

# === Start containers ===
echo "=== Starting containers ==="
PROFILES=()
if [ "${ENABLE_PHPLDAPADMIN:-false}" = "true" ]; then
  PROFILES=(--profile ui)
fi
docker compose "${PROFILES[@]}" up -d

echo ""
echo "=== Waiting for OpenLDAP ==="
for i in $(seq 1 30); do
  if docker exec openldap ldapsearch -x -H ldap://localhost:389 -b "" -s base "(objectClass=*)" namingContexts >/dev/null 2>&1; then
    echo "OpenLDAP ready on node $SERVER_ID ($ROLE)."
    break
  fi
  [ "$i" -eq 30 ] && { echo "OpenLDAP did not start in time"; docker logs openldap | tail -30; exit 1; }
  sleep 1
done

echo ""
echo "Node $SERVER_ID up. Role=$ROLE"
echo "  Direct LDAP:     ldap://<node-ip>:389"
echo "  HAProxy LDAP LB: ldap://<node-ip>:1389  (first: node1 active, node2+ backup)"
echo "  HAProxy stats:   http://<node-ip>:8404  ($HAPROXY_STATS_USER/$HAPROXY_STATS_PASSWORD)"
