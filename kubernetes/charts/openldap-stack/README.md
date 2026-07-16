# openldap-stack

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.6.13](https://img.shields.io/badge/AppVersion-2.6.13-informational?style=flat-square)

Umbrella chart for the OpenLDAP stack: OpenLDAP 2.6 server, phpLDAPadmin,
and Self Service Password. Declarative GitOps-friendly administration via
openldap-cli (https://github.com/MaximeWewer/openldap-cli).

**Homepage:** <https://github.com/MaximeWewer/OpenLDAP-docker-setup>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| MaximeWewer |  | <https://github.com/MaximeWewer> |

## Source Code

* <https://github.com/MaximeWewer/OpenLDAP-docker-setup>
* <https://github.com/MaximeWewer/openldap-cli>
* <https://github.com/MaximeWewer/OpenLDAP_prometheus_exporter>

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| file://charts/openldap | openldap | 0.1.0 |
| file://charts/phpldapadmin | phpldapadmin | 0.1.0 |
| file://charts/self-service-password | self-service-password | 0.1.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| openldap.enabled | bool | `true` |  |
| phpldapadmin.enabled | bool | `false` |  |
| self-service-password.enabled | bool | `false` |  |
