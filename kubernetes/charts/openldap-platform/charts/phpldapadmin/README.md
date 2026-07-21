# phpldapadmin

phpLDAPadmin 2.x web UI for browsing and editing the OpenLDAP directory.
Env-driven configuration; binds against the sibling openldap subchart's
Service by default.

Normally installed via the umbrella [`openldap-platform`](../..) with
`--set phpldapadmin.enabled=true`. The LDAP host defaults to the
sibling openldap Service (`<release>-openldap.<ns>.svc.cluster.local`).

## Requirements

Kubernetes: `>=1.27.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| app.keyExistingSecret | string | `""` |  |
| app.timezone | string | `"UTC"` |  |
| app.url | string | `"http://localhost:8080"` |  |
| bind.existingSecret | string | `""` |  |
| bind.username | string | `""` |  |
| extraDeploy | list | `[]` |  |
| extraEnv | list | `[]` |  |
| extraInitContainers | list | `[]` |  |
| extraVolumeMounts | list | `[]` |  |
| extraVolumes | list | `[]` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"phpldapadmin/phpldapadmin"` |  |
| image.tag | string | `"2.3.11"` |  |
| ingress.enabled | bool | `false` |  |
| ingress.gatewayAPI.gatewayClassName | string | `""` |  |
| ingress.gatewayAPI.gatewayName | string | `""` |  |
| ingress.gatewayAPI.gatewayNamespace | string | `""` |  |
| ingress.gatewayAPI.listenerName | string | `"https"` |  |
| ingress.gatewayAPI.port | int | `443` |  |
| ingress.host | string | `""` |  |
| ingress.ingressNginx.annotations | object | `{}` |  |
| ingress.ingressNginx.className | string | `"nginx"` |  |
| ingress.mode | string | `"ingress-nginx"` |  |
| ingress.tls.certManager.enabled | bool | `false` |  |
| ingress.tls.certManager.issuerRef.kind | string | `"ClusterIssuer"` |  |
| ingress.tls.certManager.issuerRef.name | string | `""` |  |
| ingress.tls.enabled | bool | `false` |  |
| ingress.tls.existingSecret | string | `""` |  |
| ldap.baseDN | string | `"dc=example,dc=org"` |  |
| ldap.connection | string | `"ldap"` |  |
| ldap.host | string | `""` |  |
| ldap.loginAttr | string | `"uid"` |  |
| ldap.port | int | `389` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| livenessProbe.initialDelaySeconds | int | `30` |  |
| livenessProbe.periodSeconds | int | `30` |  |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | string | `"http"` |  |
| readinessProbe.initialDelaySeconds | int | `5` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| replicaCount | int | `1` |  |
| resources.limits.cpu | string | `"500m"` |  |
| resources.limits.memory | string | `"512Mi"` |  |
| resources.requests.cpu | string | `"50m"` |  |
| resources.requests.memory | string | `"128Mi"` |  |
| securityContext.allowPrivilegeEscalation | bool | `false` |  |
| securityContext.capabilities.add[0] | string | `"CHOWN"` |  |
| securityContext.capabilities.add[1] | string | `"SETUID"` |  |
| securityContext.capabilities.add[2] | string | `"SETGID"` |  |
| securityContext.capabilities.add[3] | string | `"DAC_OVERRIDE"` |  |
| securityContext.capabilities.add[4] | string | `"FOWNER"` |  |
| securityContext.capabilities.add[5] | string | `"NET_BIND_SERVICE"` |  |
| securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| securityContext.readOnlyRootFilesystem | bool | `false` |  |
| service.annotations | object | `{}` |  |
| service.port | int | `8080` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automountServiceAccountToken | bool | `false` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| sidecars | list | `[]` |  |
| tolerations | list | `[]` |  |
| topologySpreadConstraints | list | `[]` |  |
