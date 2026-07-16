# OpenLDAP setup

Production-oriented OpenLDAP 2.6 deployment recipes, packaged per target platform.

## Layouts

| Target | Path | Status |
|--------|------|--------|
| **Docker Compose** | [`docker/`](docker/) | Ready — standalone, HA active-passive, HA active-active (delta-syncrepl) |
| **Kubernetes (Helm chart)** | [`kubernetes/`](kubernetes/) | Ready — umbrella chart with openldap + phpldapadmin + self-service-password subcharts, HA (standalone/mirror/multi-master, incl. cross-cluster), TLS (cert-manager/job/provided), Ingress (nginx/gateway-api), backup + accesslog-purge CronJobs, Prometheus exporter, NetworkPolicy hardening, GitOps refs (Argo CD, Flux) |

## Companion tooling

- **[openldap-cli](https://github.com/MaximeWewer/openldap-cli)** — day-to-day admin (users, groups, ppolicy, backup, diagnostics). Used by both Docker and Kubernetes layouts.
- **[OpenLDAP_prometheus_exporter](https://github.com/MaximeWewer/OpenLDAP_prometheus_exporter)** — Prometheus exporter (`cn=Monitor`). Sidecar-friendly for Kubernetes.

## Docker quick start

```bash
cd docker/standalone
bash certs.sh          # optional: generate TLS material
bash setup.sh          # bootstrap + start
```

Full documentation: [`docker/README.md`](docker/README.md).

## Kubernetes quick start

```bash
helm upgrade --install ldap kubernetes/charts/openldap-stack \
  --namespace ldap --create-namespace \
  --set openldap.mode=standalone
```

Full documentation: [`kubernetes/README.md`](kubernetes/README.md).
GitOps + cross-cluster HA: [`kubernetes/gitops/`](kubernetes/gitops/) and
[`kubernetes/cross-cluster/`](kubernetes/cross-cluster/).

## License

See [LICENSE](LICENSE).
