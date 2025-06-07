#!/bin/bash

# === LDAP configuration variables ===
LDAP_HOST="localhost"
LDAP_PORT="389"

BASE_DN="dc=example,dc=org"

# Admin account for LDAP database (data management)
LOCAL_ADMIN="cn=admin,${BASE_DN}"
LOCAL_ADMIN_PASS="adminpassword"

# Admin account for LDAP configuration
CONFIG_ADMIN="cn=adminconfig,cn=config"
CONFIG_ADMIN_PASS="adminpasswordconfig"

# Base commands
LDAPMODIFY_DATA="ldapmodify -x -a -H ldap://${LDAP_HOST}:${LDAP_PORT} -D $LOCAL_ADMIN -w $LOCAL_ADMIN_PASS"
LDAPMODIFY_CONFIG="ldapmodify -x -a -H ldap://${LDAP_HOST}:${LDAP_PORT} -D $CONFIG_ADMIN -w $CONFIG_ADMIN_PASS"

echo "=== Base data ==="
$LDAPMODIFY_DATA -f init-ldifs/01-base.ldif
$LDAPMODIFY_DATA -f init-ldifs/02-org-ou.ldif
$LDAPMODIFY_DATA -f init-ldifs/03-users.ldif
$LDAPMODIFY_DATA -f init-ldifs/04-service-accounts.ldif
$LDAPMODIFY_DATA -f init-ldifs/05-groups.ldif

echo "=== Applying ACLs ==="
$LDAPMODIFY_CONFIG -f init-ldifs/06-acl.ldif

echo "=== dynlist module ==="
$LDAPMODIFY_CONFIG -f module-dynlist/01-enable-dynlist.ldif
$LDAPMODIFY_CONFIG -f module-dynlist/02-overlay-dynlist.ldif

echo "=== memberof module ==="
$LDAPMODIFY_CONFIG -f module-memberof/01-enable-memberof.ldif
$LDAPMODIFY_CONFIG -f module-memberof/02-overlay-memberof.ldif

echo "=== ppolicy module ==="
$LDAPMODIFY_CONFIG -f module-ppolicy/01-enable-ppolicy.ldif
$LDAPMODIFY_DATA -f module-ppolicy/02-default-ppolicy.ldif
$LDAPMODIFY_CONFIG -f module-ppolicy/03-overlay-ppolicy.ldif

echo "=== refint module ==="
$LDAPMODIFY_CONFIG -f module-refint/01-enable-refint.ldif
$LDAPMODIFY_CONFIG -f module-refint/02-overlay-refint.ldif

echo "LDAP setup completed."
