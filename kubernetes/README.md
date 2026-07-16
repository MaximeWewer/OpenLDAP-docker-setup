# Kubernetes — OpenLDAP Helm chart

Helm-based deployment of the OpenLDAP stack (server + phpLDAPadmin + Self Service
Password) with declarative GitOps-friendly administration via
[openldap-cli](https://github.com/MaximeWewer/openldap-cli).

## Status

Incremental scaffold. Track progress against the roadmap below.

| PR | Scope | Status |
|----|-------|--------|
| 2 | Scaffold umbrella chart + `openldap` subchart (standalone MVP) | done |
| 3 | HA modes (mirror, multi-master, cross-cluster external peers) | current |
| 4 | Users / groups / ppolicy sync jobs + password Secret backend | pending |
| 5 | Backup CronJob + accesslog-purge + Prometheus exporter sidecar | pending |
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
