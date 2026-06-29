#!/bin/bash
# Audit: dump olcAccess rules that match a target DN/subtree.
# Output is the raw filtered ACL list - read it manually.
source "$(dirname "$0")/common.sh"

if [ -z "${1:-}" ]; then
  cat <<EOF
Usage: $0 <target-dn>
  e.g. $0 'ou=users,$BASE_DN'
       $0 'cn=admin,ou=users,$BASE_DN'
Dumps olcAccess rules from cn=config that match the given DN (subtree, dn.base,
dn.exact, dn.regex) so you can manually review who has read/write/manage rights.
EOF
  exit 1
fi

TARGET="$1"
CONFIG_PASSFILE=$(make_passfile "$CONFIG_ADMIN_PASS")

ALL=$(ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" -D "$CONFIG_ADMIN" -y "$CONFIG_PASSFILE" \
  -b "cn=config" "(olcAccess=*)" olcAccess -LLL 2>/dev/null)

echo "=== ACLs matching '$TARGET' ==="
echo "$ALL" | awk -v t="$TARGET" '
  /^dn:/         { dn = substr($0, 5); next }
  /^olcAccess:/  {
    # gather continuation lines
    rule = substr($0, 13)
    while ((getline next_line) > 0 && next_line ~ /^[[:space:]]/) {
      rule = rule " " substr(next_line, 2)
    }
    # match against target
    if (rule ~ ("dn\\.(base|exact|subtree|children|regex)?=\"?" t) || \
        index(rule, t) > 0) {
      print "DN: " dn
      print "  " rule
      print ""
    }
    # re-process the line we read
    if (next_line !~ /^[[:space:]]/) {
      if (next_line ~ /^dn:/) { dn = substr(next_line, 5) }
      else if (next_line ~ /^olcAccess:/) {
        rule = substr(next_line, 13)
        if (rule ~ ("dn\\.(base|exact|subtree|children|regex)?=\"?" t) || \
            index(rule, t) > 0) {
          print "DN: " dn
          print "  " rule
          print ""
        }
      }
    }
  }
'

echo
echo "Hint: 'manage' > 'write' > 'read' > 'auth'. Anonymous = '* none' = no access."
