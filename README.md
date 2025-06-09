# OpenLDAP docker setup

Welcome to the *OpenLDAP docker setup* ! This project provides a streamlined way to deploy an **[OpenLDAP](https://github.com/bitnami/containers/tree/main/bitnami/openldap)** server along with **[phpLDAPadmin](https://github.com/leenooks/phpLDAPadmin)** and **[self-service-password](https://github.com/ltb-project/self-service-password)** interfaces. It is designed to simplify the setup and management of an LDAP environment, making it accessible for both development and production use.

## Key features

- **Easy deployment**: With Docker Compose, you can quickly set up an OpenLDAP server, phpLDAPadmin, and self-service-password interfaces.
- **Secure communication**: Supports LDAPS for secure communication between clients and the server.
- **Pre-configured modules**: Includes modules for *dynamic lists*, *memberOf*, *referential integrity* and *password policies*.
- **Service accounts**: Dedicated organizational unit for service accounts with customizable access rights.
- **Administration scripts**: Includes scripts for managing users, groups, and service accounts.
- **LDIF-based schema configuration**: The schema is configured using LDIF files located in the `init-ldif` directory, so avoid using OpenLDAP environment variables for schema creation.

## Getting started

### Notes

- You must change all passwords
- For *phpldapadmin* and *self-service-password*, service accounts have been created and ACLs have been configured
- To login to *phpldapadmin*, the user `cn=admin,ou=users,dc=example,dc=org` is required with this configuration. Therefore, use the user `admin` and the password `admin`

### Prerequisites

- docker
- docker compose
- ldap-utils
- pwgen

### Installation

- **Generate certificates (optional)**

If you want to use LDAPS, generate the certificates by running the following command:

```bash
bash 00-certs.sh
```

- **Start the Docker containers**

Launch the Docker Compose setup with the following command:

```bash
docker compose up -d
```

- **Run the initial setup**

Execute the initial setup script to configure the OpenLDAP server:

```bash
bash 01-setup.sh
```

Once the setup is complete, you can manage the LDAP server using *ldapmodify* or *ldapadd* commands.

---

## LDAP commands

Here are some useful LDAP commands to help you manage your OpenLDAP server:

- **List data**

To list data under dc=example,dc=org, use:

```bash
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w "admin_PASSWORD" -b "dc=example,dc=org"
```

- **Add a resource**

To add a resource using ldapmodify, use:

```bash
ldapmodify -x -a -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w "admin_PASSWORD" -f CUSTOM_FILE.ldif
```

- **List modules**

To list the available modules, use:

```bash
ldapsearch -x -s one -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminconfig_PASSWORD" -b cn=config "(objectClass=olcModuleList)" olcModuleLoad -LLL
```

- **Search for configuration**

To search for specific configurations, use the following command:

```bash
ldapsearch -x -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminconfig_PASSWORD" -b "olcDatabase={2}mdb,cn=config" olcAccess
```

---

## Backup & restore

It is highly recommended to save LDIF files on an encrypted partition, as they contain sensitive information, including passwords.
Also, ensure that only authorized users have access to these files by setting appropriate permissions on the relevant machines.

- **Backup - config**

```bash
docker exec openldap bash -c "slapcat -b "cn=config" -F /bitnami/openldap/slapd.d/ > /backup/config_$(date +%Y%m%d).ldif"
```

- **Backup - data**

```bash
docker exec openldap bash -c "slapcat -b 'dc=example,dc=org' -F /bitnami/openldap/slapd.d/ > /backup/data/data_$(date +%Y%m%d).ldif"
```

- **Restore - config**

```bash
docker compose down
rm -R ./data/slap.d/*
docker run --rm -v ./data:/bitnami/openldap -v ./backup:/backup bitnami/openldap:2.6.10 bash -c 'slapadd -b "cn=config" -F /bitnami/openldap/slapd.d/ -l /backup/config_DATE.ldif'
docker compose up -d
```

- **Restore - data**

```bash
docker exec openldap bash -c "slapadd -b 'dc=example,dc=org' -F /bitnami/openldap/slapd.d/ -l /backup/data_DATE.ldif"
```

### Cronjob

```bash
# Daily backup of LDAP configuration and data at 10 p.m.
0 22 * * * docker exec openldap bash -c "slapcat -b 'cn=config' -F /bitnami/openldap/slapd.d/ > /backup/config_\$(date +\%Y\%m\%d).ldif"
0 22 * * * docker exec openldap bash -c "slapcat -b 'dc=example,dc=org' -F /bitnami/openldap/slapd.d/ > /backup/data_\$(date +\%Y\%m\%d).ldif"
```

---

## Administration scripts

This project includes several administration scripts to manage users, groups, and service accounts in your OpenLDAP setup. These scripts are designed to simplify common tasks such as creating users, changing passwords, and managing groups.

For password creation or modification, a `pwgen 24` is performed to generate a secure password, and print in stdout.

### Scripts overview

- `02-create-users.sh`: Creates one or more users in the LDAP directory. You can optionally specify a group to which the users will be added.
- `03-change-user-password.sh`: Changes the password for a specified user.
- `04-delete-users.sh`: Deletes one or more users from the LDAP directory and removes them from any groups they belong to.
- `05-create-group.sh`: Creates a group and optionally adds members to it.
- `06-add-service-account.sh`: Adds a new service account to the LDAP directory.
- `07-change-service-account-password.sh`: Changes the password for a specified service account.
- `08-delete-service-account.sh`: Deletes a service account from the LDAP directory.

### Usage examples

- **Create users**

To create users, use the `02-create-users.sh` script followed by the usernames. Optionally, you can specify a group with the `--group` option. Password generation is done automatically.

**Note:** Usernames must follow the pattern `firstname.lastname` (e.g., `john.doe`). This format is required because the script splits the username to automatically populate the `cn`, `sn`, `displayName`, and other LDAP attributes.

```bash
bash 02-create-users.sh user1.name user2.name --group=groupName
```

- **Change user password**

To change a user's password, use the `03-change-user-password.sh` script followed by the username.

```bash
bash 03-change-user-password.sh user1.name
```

- **Delete users**

To delete users, use the `04-delete-users.sh` script followed by the usernames.

```bash
bash 04-delete-users.sh user1.name user2.name
```

- **Create group**

To create a group, use the `05-create-groups.sh` script followed by the group name and optional members.

```bash
bash 05-create-groups.sh groupName user1.name user2.name
```

- **Add service account**

To add a service account, use the `06-add-service-account.sh` script followed by the service account name.

```bash
bash 06-add-service-account.sh serviceAccountName
```

- **Change service account password**

To change a service account's password, use the `07-change-service-account-password.sh` script followed by the service account name.

```bash
bash 07-change-service-account-password.sh serviceAccountName
```

- **Delete service account**

To delete a service account, use the `08-delete-service-account.sh` script followed by the service account name.

```bash
bash 08-delete-service-account.sh serviceAccountName
```

These scripts provide a convenient way to manage your LDAP directory and can be customized further to fit your specific requirements.

---

## Module configuration examples

### Enable and configure ppolicy module (done in 01-setup.sh)

To enable and configure the ppolicy module, use the following commands:

```bash
ldapmodify -x -a -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminconfig_PASSWORD" -f ppolicy-module/01-enable-ppolicy-module.ldif
```

```bash
ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w "admin_PASSWORD" -f ppolicy-module/02-default-ppolicy.ldif
```

```bash
ldapmodify -x -a -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminconfig_PASSWORD" -f ppolicy-module/03-overlay-ppolicy-module.ldif
```

---

## Service accounts

Service accounts are located in the ou=service-accounts organizational unit. After creating a service account, you need to define its access rights using an LDIF file. Here is an example:

```ldif
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {X}to dn.subtree="ou=users,dc=example,dc=org"
  by dn.exact="cn=phpldapadmin,ou=service-accounts,dc=example,dc=org" read
  by * none
```

Apply the LDIF file using the following command:

```bash
ldapmodify -x -a -H ldap://localhost:389 -D "cn=adminconfig,cn=config" -w "adminconfig_PASSWORD" -f CUSTOM_FILE.ldif
```

You can test the access rights with a command like this:

```bash
ldapsearch -x -H ldap://localhost:389 -D "cn=phpldapadmin,ou=service-accounts,dc=example,dc=org" -w "phpldapadmin_PASSWORD" -b "ou=users,dc=example,dc=org" "(memberOf=cn=demo,ou=groups,dc=example,dc=org)"
```

---

## Use OpenLDAP as users catalog for IAM solution (ex: Zitadel)

- **Connection settings**

Servers: `ldap://IP_or_FQDN:389` (adjust for LDAPS)

BaseDn: `dc=example,dc=org`

BindDn: `cn=admin,ou=users,dc=example,dc=org` You could create service-account with right ACL instead of using `cn=admin,ou=users,dc=example,dc=org`

BindPassword: `admin_PASSWORD`

- **User binding settings**

User binding: `cn`

User filter: `uid`

User object `classes: inetOrgPerson`

- **LDAP attributes**

ID attribute: `uid`

Displayname attribute: `displayName`

Email attribute: `mail`

Given name attribute: `givenName`

Family name attribute: `sn`

Nickname attribute: `givenName`

---

## Conclusion

This setup provides a robust and flexible LDAP environment that can be easily integrated with other systems and applications. Enjoy managing your LDAP server with ease !
