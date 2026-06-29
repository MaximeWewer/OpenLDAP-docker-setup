#!/bin/bash
# Create or update a ppolicy under ou=policies.
source "$(dirname "$0")/common.sh"

usage() {
  cat <<EOF
Usage: $0 policy-name [options]

Options (any subset):
  --max-failure=N        pwdMaxFailure        (default: 5)
  --lockout              pwdLockout: TRUE     (enable lockout)
  --no-lockout           pwdLockout: FALSE
  --lockout-duration=S   pwdLockoutDuration   seconds (0 = manual unlock)
  --failure-window=S     pwdFailureCountInterval seconds
  --min-length=N         pwdMinLength
  --max-age=S            pwdMaxAge            seconds (0 = never expires)
  --expire-warning=S     pwdExpireWarning     seconds
  --grace=N              pwdGraceAuthnLimit   logins after expiry
  --history=N            pwdInHistory         remembered passwords
  --check-quality=N      pwdCheckQuality      (0/1/2)
  --allow-self           pwdAllowUserChange: TRUE
  --no-allow-self        pwdAllowUserChange: FALSE
  --safe-modify          pwdSafeModify: TRUE  (require current pwd on change)
EOF
  exit 1
}

[ -z "${1:-}" ] && usage
POLICY_NAME="$1"
shift

declare -A KV
KV[pwdAttribute]="userPassword"
KV[pwdMaxFailure]="5"
KV[pwdLockout]="TRUE"
KV[pwdLockoutDuration]="900"
KV[pwdFailureCountInterval]="600"
KV[pwdMinLength]="12"
KV[pwdAllowUserChange]="TRUE"

for arg in "$@"; do
  case "$arg" in
    --max-failure=*)       KV[pwdMaxFailure]="${arg#--max-failure=}" ;;
    --lockout)             KV[pwdLockout]="TRUE" ;;
    --no-lockout)          KV[pwdLockout]="FALSE" ;;
    --lockout-duration=*)  KV[pwdLockoutDuration]="${arg#--lockout-duration=}" ;;
    --failure-window=*)    KV[pwdFailureCountInterval]="${arg#--failure-window=}" ;;
    --min-length=*)        KV[pwdMinLength]="${arg#--min-length=}" ;;
    --max-age=*)           KV[pwdMaxAge]="${arg#--max-age=}" ;;
    --expire-warning=*)    KV[pwdExpireWarning]="${arg#--expire-warning=}" ;;
    --grace=*)             KV[pwdGraceAuthnLimit]="${arg#--grace=}" ;;
    --history=*)           KV[pwdInHistory]="${arg#--history=}" ;;
    --check-quality=*)     KV[pwdCheckQuality]="${arg#--check-quality=}" ;;
    --allow-self)          KV[pwdAllowUserChange]="TRUE" ;;
    --no-allow-self)       KV[pwdAllowUserChange]="FALSE" ;;
    --safe-modify)         KV[pwdSafeModify]="TRUE" ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $arg"; usage ;;
  esac
done

POLICIES_OU="ou=policies,$BASE_DN"
POLICY_DN="cn=$POLICY_NAME,$POLICIES_OU"
ADMIN_PASSFILE=$(make_passfile "$LOCAL_ADMIN_PASS")

EXISTS="no"
ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" \
  -b "$POLICY_DN" -s base "(objectClass=*)" dn -LLL 2>/dev/null | grep -q '^dn:' && EXISTS="yes"

TMP=$(make_tmpfile)
if [ "$EXISTS" = "yes" ]; then
  echo "=== Updating $POLICY_DN ==="
  {
    echo "dn: $POLICY_DN"
    echo "changetype: modify"
    first=1
    for k in "${!KV[@]}"; do
      [ "$first" = "1" ] || echo "-"
      echo "replace: $k"
      echo "$k: ${KV[$k]}"
      first=0
    done
  } > "$TMP"
else
  echo "=== Creating $POLICY_DN ==="
  {
    echo "dn: $POLICY_DN"
    echo "objectClass: pwdPolicy"
    echo "objectClass: device"
    echo "cn: $POLICY_NAME"
    for k in "${!KV[@]}"; do
      echo "$k: ${KV[$k]}"
    done
  } > "$TMP"
fi

ldapmodify -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$LOCAL_ADMIN_DN" -y "$ADMIN_PASSFILE" -a -f "$TMP"
echo "Done."
