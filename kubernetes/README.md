# Kubernetes — OpenLDAP Helm chart

Helm-based deployment of the OpenLDAP stack (server + phpLDAPadmin + Self Service
Password) with declarative GitOps-friendly administration via
[openldap-cli](https://github.com/MaximeWewer/openldap-cli).

## Status

Incremental scaffold. Track progress against the roadmap below.

| PR | Scope | Status |
|----|-------|--------|
| 2 | Scaffold umbrella chart + `openldap` subchart (standalone MVP) | done |
| 3 | HA modes (mirror, multi-master, cross-cluster external peers) | done |
| 4 | Users / groups / ppolicy sync jobs + password Secret backend | done |
| 5 | Backup CronJob + accesslog-purge + Prometheus exporter sidecar | current |
| 6 | Ingress (ingress-nginx + Gateway API) + cert-manager / cert Job | pending |
| 7 | Hardening pass (NetworkPolicy, PSA restricted, PDB, seccomp) | pending |
| 8 | `phpldapadmin` subchart | pending |
| 9 | `self-service-password` subchart | pending |
| 10 | GitOps guides (Argo CD + Flux) + cross-cluster bootstrap doc | pending |

## Layout

```
kubernetes/
└── charts/
    └── openldap-stack/            # umbrella
        ├── Chart.yaml
        ├── values.yaml            # global toggles + per-subchart overrides
        └── charts/
            └── openldap/          # OpenLDAP StatefulSet + bootstrap
                ├── Chart.yaml
                ├── values.yaml
                └── templates/
```

Later PRs add `charts/openldap-stack/charts/phpldapadmin/` and
`charts/openldap-stack/charts/self-service-password/`.

## Users, groups & policies (GitOps)

`openldap.users`, `openldap.groups` and `openldap.policies` are the declarative
source of truth for the directory content. On every `helm install/upgrade`
three post-install/upgrade Jobs (`ppolicy` → weight 5, `users` → 10,
`groups` → 15) drive [openldap-cli](https://github.com/MaximeWewer/openldap-cli)
against the LDAP Service to reconcile the tree with the values.

- **Passwords are auto-generated per user** (`openssl rand`) unless a
  Secret is referenced via `existingSecret`. Generated passwords are
  stored under `<release>-openldap-user-<uid>` (key `password`) with
  the label `openldap.stack/user=<uid>` — the chart never reads them back
  itself, admins retrieve them once via `kubectl get secret`.
- **Attributes reconcile** on every upgrade (`openldap-cli user set …`),
  so editing values.yaml is the update path.
- **Drift cleanup** — a user removed from `openldap.users` is either
  hard-deleted (`onUserRemove: delete`, default) or locked via
  `pwdAccountLockedTime` (`onUserRemove: lock`). Same knob for groups
  via `onGroupRemove`.
- **Group membership** is expressed on the group side (`groups[*].members`
  is a list of UIDs); the `memberOf` overlay auto-populates the user
  entry so both directions stay consistent.
- **ppolicy templates** are set via `openldap-cli ppolicy set` — the
  entry keys map 1:1 to the CLI flags (`min-length`, `max-age`,
  `lockout`, …), and `users[].policy` triggers a `ppolicy assign`.

```yaml
openldap:
  users:
    - uid: alice
      givenName: Alice
      sn: Wonderland
      mail: alice@example.org
      policy: strong        # optional — matches a policy cn below
      attrs:                # optional — free-form extra --set k=v
        title: Engineer
  groups:
    - cn: devs
      description: Development team
      members: [alice, bob] # UIDs (must be declared in users OR exist in LDAP)
  policies:
    - cn: strong
      min-length: 12
      max-age: 7776000
      max-failure: 5
      lockout: true
```

The sync Jobs install `openldap-cli` + `kubectl` from GitHub / dl.k8s.io
into a plain Alpine image at Job startup — no custom image build needed.
Their ServiceAccount is scoped strictly to Secret CRUD in the release
namespace (see `templates/rbac-sync.yaml`).

## Backup & retention

`openldap.backup.enabled: true` provisions a daily CronJob that dumps the
data and cn=config databases as gzipped LDIF via `openldap-cli backup`.
Files land on a chart-managed PVC (or an existing one via
`persistence.existingClaim`) and are pruned after
`openldap.backup.retentionDays` days.

```yaml
openldap:
  backup:
    enabled: true
    schedule: "0 22 * * *"        # every night at 22:00
    retentionDays: 30
    persistence:
      size: 20Gi
      storageClass: ""            # cluster default
    includeOperational: true      # pass --operational to backup data
```

Restoring: `kubectl cp` a dump out of the PVC, then run
`openldap-cli backup restore <file>` against a fresh install.

## Accesslog purge

The slapd built-in `olcAccessLogPurge` deletes accesslog entries but does
NOT reclaim MDB space (LMDB is copy-on-write, deleted pages stay allocated
until an offline reload). `openldap.accesslogPurgeJob.enabled: true`
schedules a weekly `openldap-cli ops accesslog-purge` that shrinks the
accesslog MDB in place.

```yaml
openldap:
  accesslogPurgeJob:
    enabled: true
    schedule: "0 3 * * 0"         # Sundays 03:00
    keepDays: 7
    sweep: "00+06:00"
```

## Prometheus monitoring

`openldap.monitoring.enabled: true` adds a sidecar
[OpenLDAP_prometheus_exporter](https://github.com/MaximeWewer/OpenLDAP_prometheus_exporter)
to every StatefulSet pod, publishes port 9330 on the LDAP Service, and
optionally emits a `ServiceMonitor` + `PrometheusRule` for
prometheus-operator installs.

```yaml
openldap:
  monitoring:
    enabled: true
    exporter:
      extraEnv:
        - name: OPENLDAP_METRICS_EXCLUDE
          value: "sasl,log"
    serviceMonitor:
      enabled: true
      interval: 30s
      labels:
        release: kube-prometheus-stack
    prometheusRule:
      enabled: true
```

Default alerts shipped with `prometheusRule.enabled=true`: `OpenLDAPDown`,
`OpenLDAPScrapeErrors`, `OpenLDAPTLSCertExpiringSoon`,
`OpenLDAPReplicationLagHigh`, `OpenLDAPAccountLockouts`.

The exporter binds as `cn=adminconfig,cn=config` (config-admin has the
`cn=Monitor` read ACL seeded by bootstrap); its password is read from the
same `<release>-openldap-admin` Secret via `LDAP_PASSWORD_FILE`.

## HA modes

`openldap.mode` selects the replication topology. All modes use delta-syncrepl
(`syncdata=accesslog`) with `olcMirrorMode: TRUE` under the hood; the
difference is the number of replicas and how clients balance across them.

| Mode | Replicas | Use case |
|------|----------|----------|
| `standalone` | 1 | Dev, single-node prod, PoC |
| `mirror` | 2 | Active/passive HA — clients pin one node, failover on outage |
| `multi-master` | N ≥ 2 | Active/active HA — writes accepted anywhere, mesh replication |

```bash
# 3-way multi-master
helm upgrade --install ldap kubernetes/charts/openldap-stack/ \
  --namespace ldap --create-namespace \
  --set openldap.mode=multi-master \
  --set openldap.replicaCount=3
```

**Cross-cluster HA** — every peer needs an outside-reachable LDAP(S)
endpoint (see PR 6 for ingress). Set `openldap.replication.externalPeers`
to the FQDNs of nodes in the other cluster(s), and pick a distinct
`serverIdBase` per cluster so `olcServerID` stays globally unique:

```yaml
# Cluster DC1
openldap:
  mode: multi-master
  replicaCount: 3
  replication:
    serverIdBase: 1                      # nodes get IDs 1, 2, 3
    externalPeers:
      - ldaps://ldap.dc2.example.com:636

# Cluster DC2
openldap:
  mode: multi-master
  replicaCount: 3
  replication:
    serverIdBase: 10                     # nodes get IDs 10, 11, 12
    externalPeers:
      - ldaps://ldap.dc1.example.com:636
```

The replicator service account (`cn=replicator,ou=service-accounts,…` by
default) is seeded on ordinal-0 during bootstrap and syncs to every peer;
its password is auto-generated and stored in `<release>-openldap-replicator`
(preserved across upgrades). Override with an existing Secret via
`openldap.replication.replicator.existingSecret`.

## Quick start (standalone)

```bash
# Render locally to inspect
helm template ldap kubernetes/charts/openldap-stack/ \
  --set openldap.directory.suffix=dc=example,dc=org

# Install
helm upgrade --install ldap kubernetes/charts/openldap-stack/ \
  --namespace ldap --create-namespace \
  --set openldap.directory.suffix=dc=example,dc=org

# Retrieve auto-generated admin passwords
kubectl -n ldap get secret ldap-openldap-admin \
  -o jsonpath='{.data.admin-password}' | base64 -d ; echo
kubectl -n ldap get secret ldap-openldap-admin \
  -o jsonpath='{.data.config-admin-password}' | base64 -d ; echo

# Port-forward and test
kubectl -n ldap port-forward svc/ldap-openldap 389:389
ldapsearch -x -H ldap://localhost:389 -D cn=admin,dc=example,dc=org -W \
  -b dc=example,dc=org '(objectClass=*)'
```

## Design principles

- **Declarative first** — every knob in `values.yaml`, GitOps-agnostic (Argo CD, Flux, or plain `helm`).
- **openldap-cli everywhere** — bootstrap Jobs use the CLI for user/group/ppolicy management.
- **Multi-backend** — TLS via `cert-manager` **or** self-managed CronJob (no hard dep on cert-manager). Secrets via Kubernetes Secrets **or** External Secrets Operator.
- **HA-ready** — `mode: standalone | mirror | multi-master`, with optional cross-cluster `externalPeers` for geo-replication.
- **Hardened by default** — non-root, drop ALL caps, NetworkPolicy, PDB, PSA `restricted`.
- **No operator** — reconciliation left to the GitOps runner (Argo/Flux drift detection).

See root [README](../README.md) for the Docker Compose alternative.
