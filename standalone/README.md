# Standalone — OpenLDAP mono-instance

Single-host deployment of OpenLDAP 2.6 + phpLDAPadmin + Self Service Password via Docker Compose.

## Usage

```bash
# Optional: generate TLS certs
bash certs.sh

# Bootstrap config + initial data + start containers
bash setup.sh

# Wipe and reinitialize
bash setup.sh --reset
```

## Services

| Service               | URL                    | Default login                                           |
| --------------------- | ---------------------- | ------------------------------------------------------- |
| OpenLDAP              | `ldap://localhost:389` | `cn=admin,ou=users,dc=example,dc=org` / `adminpassword` |
| phpLDAPadmin          | http://localhost:8080  | `admin` / `adminpassword`                               |
| Self Service Password | http://localhost:8088  | Any LDAP user                                           |

## Files

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | OpenLDAP + phpLDAPadmin + SSP |
| `setup.sh` | Bootstrap (`slapadd` cn=config + data, fix perms, `docker compose up`) |
| `init-config/slapd-config.ldif` | Full `cn=config` (modules, schemas, ACLs, overlays, accesslog) |
| `ssp.conf.php` | Self Service Password configuration |
| `data/` | Persistent OpenLDAP data (`slapd.d`, MDB, accesslog) — gitignored |

Shared with other modes (parent directory):

| Path | Purpose |
|------|---------|
| `../common.sh` | Shared bash helpers |
| `../base-ldifs/` | Base directory data (users, groups, policies) |
| `certs.sh` + `certs/` | TLS certificate generation + material |
| `backup/` | Backup dump location |
| `../admin scripts` | Admin scripts (users/groups/service-accounts) |
