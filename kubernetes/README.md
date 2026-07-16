# Kubernetes — OpenLDAP Helm chart

Helm-based deployment of the OpenLDAP stack (server + phpLDAPadmin + Self Service
Password) with declarative GitOps-friendly administration via
[openldap-cli](https://github.com/MaximeWewer/openldap-cli).

## Status

Incremental scaffold. Track progress against the roadmap below.

| PR | Scope | Status |
|----|-------|--------|
| 2 | Scaffold umbrella chart + `openldap` subchart (standalone MVP) | current |
| 3 | HA modes (mirror, multi-master, cross-cluster external peers) | pending |
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

## Quick start (standalone MVP)

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
