# Values reference

The authoritative source for every knob is the annotated `values.yaml`
of each subchart:

- [openldap `values.yaml`](../charts/openldap-stack/charts/openldap/values.yaml)
- [phpldapadmin `values.yaml`](../charts/openldap-stack/charts/phpldapadmin/values.yaml)
- [self-service-password `values.yaml`](../charts/openldap-stack/charts/self-service-password/values.yaml)
- [umbrella `values.yaml`](../charts/openldap-stack/values.yaml)

Comments in those files describe defaults, valid range, side effects on
other knobs, and example blocks.

## Generating a Markdown table

For downstream docs, generate a full table with
[helm-docs](https://github.com/norwoodj/helm-docs):

```bash
go install github.com/norwoodj/helm-docs/cmd/helm-docs@latest
helm-docs --chart-search-root=kubernetes/charts/openldap-stack \
          --template-files=README.md.gotmpl \
          --output-file=VALUES.md
```

Every value with a `# --` docstring gets emitted; the chart's comments
already follow that convention.

## Most-tuned values

The subset that changes most often across environments — a starting
overlay if you want to skim before opening the full files.

| Value | Default | Notes |
|-------|---------|-------|
| `openldap.mode` | `standalone` | `standalone` \| `mirror` \| `multi-master` |
| `openldap.replicaCount` | `1` | Must match `mode` (1/2/N≥2) |
| `openldap.directory.suffix` | `dc=example,dc=org` | Root of the tree |
| `openldap.admin.bindDN` | `cn=admin,dc=example,dc=org` | rootDN of the main DB |
| `openldap.admin.existingSecret` | `""` | Point at ESO / SealedSecret in prod |
| `openldap.persistence.size` | `10Gi` | PVC size per replica |
| `openldap.database.main.maxSizeBytes` | 1 GiB | Bump for > 100k entries |
| `openldap.database.accesslog.maxSizeBytes` | 1 GiB | #1 prod incident source; size to writes/sec |
| `openldap.accesslog.ops` | `writes bind` | Drop `bind` for high-traffic setups |
| `openldap.replication.serverIdBase` | `1` | Distinct per cluster in cross-cluster HA |
| `openldap.replication.externalPeers` | `[]` | Cross-cluster LDAPS URIs |
| `openldap.tls.enabled` | `false` | Turn on before any prod use |
| `openldap.tls.backend` | `cert-manager` | `cert-manager` \| `job` \| `provided` |
| `openldap.ingress.enabled` | `false` | Only LDAPS is routed |
| `openldap.ingress.host` | `""` | Required when ingress is enabled |
| `openldap.backup.enabled` | `false` | Daily CronJob, PVC-backed |
| `openldap.monitoring.enabled` | `false` | Sidecar exporter + optional SM/PR |
| `openldap.networkPolicy.enabled` | `false` | Default-deny + explicit allows |
| `openldap.podDisruptionBudget.enabled` | `auto` | Enabled iff HA |
| `openldap.users` | `[]` | Declarative user list (sync Job reconciles) |
| `openldap.groups` | `[]` | Declarative group list |
| `openldap.policies` | `[]` | Declarative ppolicy templates |
| `openldap.onUserRemove` | `delete` | `delete` \| `lock` |
| `phpldapadmin.enabled` | `false` | UI subchart |
| `self-service-password.enabled` | `false` | End-user password UI |
