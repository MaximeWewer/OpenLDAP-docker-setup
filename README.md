# OpenLDAP docker setup

A streamlined way to deploy an **[OpenLDAP](https://openldap.org/)** server along with **[phpLDAPadmin](https://github.com/leenooks/phpLDAPadmin)** and **[Self Service Password](https://github.com/ltb-project/self-service-password)** using Docker Compose. Built on the minimal [cleanstart/openldap](https://hub.docker.com/r/cleanstart/openldap) image (OpenLDAP 2.6).

## Key features

- **Minimal image**: Uses `cleanstart/openldap` — no shell, no bootstrap scripts, full control via `slapadd`
- **Secure by default**: Least-privilege ACLs per OU, SSHA-hashed rootDN passwords, ECDSA P-384 TLS certificates, isolated Docker network
- **Pre-configured overlays**: memberof, referential integrity, password policy, dynamic lists
- **Service accounts**: Dedicated OU with per-account ACL injection via scripts
- **POSIX optional**: POSIX support (posixAccount/shadowAccount) available via opt-in flag
- **Administration scripts**: Manage users, groups, and service accounts from the command line

## Architecture

```
dc=example,dc=org
  |-- ou=users                 # User accounts (inetOrgPerson)
  |-- ou=groups                # Groups (groupOfNames)
  |-- ou=service-accounts      # Service accounts (phpldapadmin, ssp, custom)
  |-- ou=policies              # Password policies
```

### ACL matrix (least privilege)

**Main database** (`dc=example,dc=org`):

| Identity         | userPassword | service-accounts | users | groups | policies | base DN |
| ---------------- | ------------ | ---------------- | ----- | ------ | -------- | ------- |
| self             | write        | -                | write | -      | -        | -       |
| admin (ou=users) | write        | write            | write | write  | read     | write   |
| adminconfig      | -            | -                | read  | -      | -        | -       |
| ssp              | write        | -                | -     | -      | read     | -       |
| phpldapadmin     | -            | -                | read  | read   | read     | -       |
| anonymous        | auth only    | -                | -     | -      | read     | read    |

**Infrastructure databases**:

| Identity    | cn=config | cn=accesslog | cn=Monitor |
| ----------- | --------- | ------------ | ---------- |
| adminconfig | manage    | read         | read       |
| *           | -         | -            | -          |

Users and applications that need read access to `ou=users` or `ou=groups` must use a dedicated service account (see [Service accounts](#service-accounts)).

## Getting started

### Prerequisites

- Docker & Docker Compose
- `ldap-utils` (`ldapsearch`, `ldapadd`, `ldapmodify`, `ldapdelete`)
- `pwgen`

### Installation

1. **Generate certificates** (optional, for TLS)

```bash
bash 00-certs.sh
```

2. **Run the setup**

This bootstraps the configuration via `slapadd`, loads initial data, and starts the containers:

```bash
bash 01-setup.sh
```

To reinitialize from scratch:

```bash
bash 01-setup.sh --reset
```

3. **Access the services**

| Service               | URL                    | Default login                                           |
| --------------------- | ---------------------- | ------------------------------------------------------- |
| OpenLDAP              | `ldap://localhost:389` | `cn=admin,ou=users,dc=example,dc=org` / `adminpassword` |
| phpLDAPadmin          | http://localhost:8080  | `admin` / `adminpassword`                               |
| Self Service Password | http://localhost:8088  | Any LDAP user                                           |

> **Important**: Change all default passwords before production use.

4. **Change default passwords**

```bash
# Change admin user password (cn=admin,ou=users)
bash 03-change-user-password.sh admin

# Change config admin password (cn=adminconfig,cn=config)
# Generate a new SSHA hash:
docker run --rm --entrypoint slappasswd cleanstart/openldap:2.6.13 -s "NEW_PASSWORD"
# Then update the rootDN password:
ldapmodify -x -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminpasswordconfig" <<EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: {SSHA}PASTE_HASH_HERE
EOF

# Change data rootDN password (cn=admin,dc=example,dc=org)
ldapmodify -x -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminpasswordconfig" <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: {SSHA}PASTE_HASH_HERE
EOF
```

> After changing the config admin password, update `CONFIG_ADMIN_PASS` in `common.sh`.
> After changing the data rootDN password, it does not affect `LOCAL_ADMIN_PASS` (scripts use the admin user, not the rootDN).

## Project structure

```
.
|-- common.sh                             # Shared configuration and helpers
|-- 00-certs.sh                           # TLS certificate generation (ECDSA P-384)
|-- 01-setup.sh                           # Bootstrap and start (slapadd + docker compose)
|-- 02-create-users.sh                    # Create users [--group=name] [--posix]
|-- 03-change-user-password.sh            # Change user password
|-- 04-delete-users.sh                    # Delete users (+ group cleanup)
|-- 05-create-group.sh                    # Create group with members
|-- 06-add-service-account.sh             # Create service account + inject ACL
|-- 07-change-service-account-password.sh # Change service account password
|-- 08-delete-service-account.sh          # Delete service account + cleanup ACL
|-- docker-compose.yml
|-- ssp.conf.php                          # Self Service Password configuration
|-- init-config/
|   |-- slapd-config.ldif                 # Full cn=config (modules, schemas, ACLs, overlays)
|-- init-ldifs/
|   |-- 01-base.ldif                      # Base DN
|   |-- 02-org-ou.ldif                    # Organizational units
|   |-- 03-users.ldif                     # Default users
|   |-- 04-service-accounts.ldif          # phpldapadmin & ssp accounts
|   |-- 05-groups.ldif                    # Default groups
|   |-- 06-default-ppolicy.ldif           # Password policy
|-- certs/                                # TLS certificates
|-- data/                                 # Persistent data (slapd.d + MDB)
|-- backup/                               # Backup directory
```

## Administration scripts

All scripts source `common.sh` for shared configuration (`set -euo pipefail`, LDAP connection, helpers). Passwords are never passed via `-w` on the command line (uses `-y` with temp files). Temp files are cleaned up on exit via `trap`.

All scripts use `cn=admin,ou=users,dc=example,dc=org` (subject to ACLs, not the rootDN).

Passwords are generated with `pwgen -s -y -r '#<>\ "'"'"' 32` (32 chars, symbols, LDIF-safe).

### Create users

Usernames must follow the `firstname.lastname` pattern. The script auto-populates `cn`, `sn`, `givenName`, `displayName`, and `mail`.

```bash
# Standard (inetOrgPerson only)
bash 02-create-users.sh john.doe jane.smith --group=demo

# With POSIX attributes (requires nis schema enabled in slapd-config.ldif)
bash 02-create-users.sh john.doe jane.smith --group=demo --posix
```

### Change user password

```bash
bash 03-change-user-password.sh john.doe
```

### Delete users

Automatically removes the user from all groups before deletion:

```bash
bash 04-delete-users.sh john.doe jane.smith
```

### Create group

At least one member is required (`groupOfNames` schema constraint):

```bash
bash 05-create-group.sh groupName john.doe jane.smith
```

### Service accounts

Create a service account with specific access rights. The script creates the account in `ou=service-accounts` and injects the access rule into the existing ACL for the target subtree:

```bash
# Read access to ou=users
bash 06-add-service-account.sh gitea --access read --subtree "ou=users,dc=example,dc=org"

# Write access to ou=groups
bash 06-add-service-account.sh myapp --access write --subtree "ou=groups,dc=example,dc=org"
```

Change password:

```bash
bash 07-change-service-account-password.sh gitea
```

Delete (also cleans up ACL references):

```bash
bash 08-delete-service-account.sh gitea
```

## POSIX support

POSIX attributes (`posixAccount`, `shadowAccount`, `uidNumber`, `gidNumber`, `homeDirectory`, `loginShell`) are **disabled by default**.

To enable POSIX support, uncomment these lines in `init-config/slapd-config.ldif` before running `01-setup.sh`:

```ldif
# Schema
#include: file:///etc/openldap/schema/nis.ldif

# Index
#olcDbIndex: uidNumber,gidNumber eq

# ACL (insert as {1}, shift subsequent indexes)
#olcAccess: {1}to attrs=shadowLastChange by self write by * read
```

Then use `--posix` when creating users:

```bash
bash 02-create-users.sh john.doe --posix
```

## TLS / LDAPS

1. Generate certificates:

```bash
bash 00-certs.sh
```

2. Uncomment the TLS lines in `init-config/slapd-config.ldif` (in the `cn=config` entry):

```ldif
olcTLSCACertificateFile: /etc/openldap/certs/openldapCA.crt
olcTLSCertificateFile: /etc/openldap/certs/openldap.crt
olcTLSCertificateKeyFile: /etc/openldap/certs/openldap.key
olcTLSVerifyClient: never
```

3. Uncomment the `command` line in `docker-compose.yml` to enable `ldaps://`:

```yaml
command: ["slapd", "-d", "0", "-h", "ldap:// ldaps://", "-F", "/etc/openldap/slapd.d"]
```

4. If using phpLDAPadmin over LDAPS, update the env vars in `docker-compose.yml`:

```yaml
- LDAP_CONNECTION=ldaps
- LDAP_PORT=636
```

5. Test:

```bash
# LDAPS
LDAPTLS_CACERT=./certs/openldapCA.crt ldapsearch -x -H ldaps://localhost:636 -D "cn=admin,ou=users,dc=example,dc=org" -w "adminpassword" -b "dc=example,dc=org"
```

> **Note**: If TLS is enabled after initial setup (without `--reset`), you can add the TLS config at runtime via `ldapmodify` on `cn=config` without re-bootstrapping.

## Backup & restore

> Store backup files on an encrypted partition — they contain password hashes.

### Backup

Since `cleanstart/openldap` has no shell, backups are done via `tar` in an alpine container:

```bash
# Config backup
docker run --rm -v ./data/slapd.d:/slapd.d:ro -v ./backup:/backup alpine:latest \
  sh -c "tar czf /backup/config_$(date +%Y%m%d).tar.gz -C /slapd.d ."

# Data backup
docker run --rm -v ./data/openldap-data:/data:ro -v ./backup:/backup alpine:latest \
  sh -c "tar czf /backup/data_$(date +%Y%m%d).tar.gz -C /data ."

# Accesslog backup
docker run --rm -v ./data/accesslog-data:/data:ro -v ./backup:/backup alpine:latest \
  sh -c "tar czf /backup/accesslog_$(date +%Y%m%d).tar.gz -C /data ."
```

### Restore

```bash
docker compose down

# Clean existing data
docker run --rm -v ./data:/data alpine:latest \
  sh -c "rm -rf /data/slapd.d/* /data/openldap-data/* /data/accesslog-data/*"

# Restore config
docker run --rm -v ./data/slapd.d:/slapd.d -v ./backup:/backup alpine:latest \
  sh -c "tar xzf /backup/config_DATE.tar.gz -C /slapd.d"

# Restore data
docker run --rm -v ./data/openldap-data:/data -v ./backup:/backup alpine:latest \
  sh -c "tar xzf /backup/data_DATE.tar.gz -C /data"

# Restore accesslog
docker run --rm -v ./data/accesslog-data:/data -v ./backup:/backup alpine:latest \
  sh -c "tar xzf /backup/accesslog_DATE.tar.gz -C /data"

# Fix permissions
docker run --rm \
  -v ./data/slapd.d:/slapd.d \
  -v ./data/openldap-data:/data \
  -v ./data/accesslog-data:/alog \
  alpine:latest sh -c "chown -R 101:102 /slapd.d /data /alog"

docker compose up -d
```

### Cronjob

```bash
# Daily backup at 10 PM + cleanup after 30 days
0 22 * * * cd /path/to/OpenLDAP-docker-setup && docker run --rm -v ./data/slapd.d:/slapd.d:ro -v ./backup:/backup alpine:latest sh -c "tar czf /backup/config_$(date +\%Y\%m\%d).tar.gz -C /slapd.d ."
0 22 * * * cd /path/to/OpenLDAP-docker-setup && docker run --rm -v ./data/openldap-data:/data:ro -v ./backup:/backup alpine:latest sh -c "tar czf /backup/data_$(date +\%Y\%m\%d).tar.gz -C /data ."
0 22 * * * cd /path/to/OpenLDAP-docker-setup && docker run --rm -v ./data/accesslog-data:/data:ro -v ./backup:/backup alpine:latest sh -c "tar czf /backup/accesslog_$(date +\%Y\%m\%d).tar.gz -C /data ."
0 23 * * * find /path/to/OpenLDAP-docker-setup/backup -name "*.tar.gz" -mtime +30 -delete
```

## LDAP commands reference

```bash
# List all entries
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,ou=users,dc=example,dc=org" -w "adminpassword" -b "dc=example,dc=org"

# List modules
ldapsearch -x -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminpasswordconfig" \
  -b cn=config "(objectClass=olcModuleList)" olcModuleLoad -LLL

# View ACLs
ldapsearch -x -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminpasswordconfig" \
  -b "olcDatabase={1}mdb,cn=config" olcAccess -LLL

# Test service account access
ldapsearch -x -H ldap://localhost:389 -D "cn=gitea,ou=service-accounts,dc=example,dc=org" -w "PASSWORD" \
  -b "ou=users,dc=example,dc=org" "(uid=john.doe)" cn mail
```

## Integration example (Zitadel, Gitea, etc.)

Create a dedicated service account instead of using the admin account:

```bash
bash 06-add-service-account.sh myapp --access read --subtree "ou=users,dc=example,dc=org"
```

Then configure your application with:

| Setting           | Value                                            |
| ----------------- | ------------------------------------------------ |
| Server            | `ldap://IP_or_FQDN:389`                          |
| Base DN           | `dc=example,dc=org`                              |
| Bind DN           | `cn=myapp,ou=service-accounts,dc=example,dc=org` |
| Bind Password     | _(generated by the script)_                      |
| User filter       | `(uid=%s)`                                       |
| User object class | `inetOrgPerson`                                  |
| ID attribute      | `uid`                                            |
| Display name      | `displayName`                                    |
| Email             | `mail`                                           |
| First name        | `givenName`                                      |
| Last name         | `sn`                                             |

## Monitoring

The `back_monitor` module is enabled in `slapd-config.ldif`. It exposes server statistics via `cn=Monitor` (connections, operations, threads, etc.), accessible with the config admin credentials:

```bash
ldapsearch -x -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminpasswordconfig" \
  -b "cn=Monitor" "(objectClass=*)" -LLL
```

To expose these metrics to Prometheus, use the [OpenLDAP Prometheus Exporter](https://github.com/MaximeWewer/OpenLDAP_prometheus_exporter). It connects to `cn=Monitor` and serves metrics on an HTTP endpoint for Prometheus scraping.

## Password policy

The default password policy (`cn=defaultppolicy,ou=policies`) enforces:

| Rule                       | Value                   |
| -------------------------- | ----------------------- |
| Minimum length             | 16 characters           |
| Quality check              | Enabled                 |
| Max age                    | 365 days                |
| Expiry warning             | 7 days before           |
| History                    | 5 passwords             |
| Lockout after              | 3 failed attempts       |
| Lockout duration           | 30 minutes              |
| Must change on first login | Yes                     |
| Cleartext passwords        | Auto-hashed server-side |
