# OpenLDAP setup

Production-oriented OpenLDAP 2.6 deployment recipes, packaged per target platform.

## Layouts

| Target | Path | Status |
|--------|------|--------|
| **Docker Compose** | [`docker/`](docker/) | Ready — standalone, HA active-passive, HA active-active (delta-syncrepl) |
| **Kubernetes (Helm chart)** | [`kubernetes/`](kubernetes/) | Work in progress — see `kubernetes/README.md` when available |

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

## License

See [LICENSE](LICENSE).
