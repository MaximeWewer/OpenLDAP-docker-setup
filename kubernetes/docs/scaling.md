# Scaling the OpenLDAP writable pool

The chart supports **fully automatic** horizontal scaling of the
writable StatefulSet in `mode: multi-master`. Three orthogonal knobs:

1. **Manual** — set `openldap.replicaCount` and `helm upgrade`.
2. **HPA** — resource + custom-metric-driven autoscaling.
3. **`scaleSchedule`** — cron-driven adjustment of the HPA min/max window
   (business-hour ramp-up, off-hour cooldown).

All three trigger the **bootstrap reconcile branch** on existing pods so
`cn=config` peer list is rebuilt without any manual `kubectl` step. The
data database (`mdb`) is preserved.

## Constraints

- Only `mode: multi-master` scales. The chart fails render if you try
  `hpa.enabled=true` with `standalone` or `mirror` (both enforce fixed
  `replicaCount` — 1 and 2 respectively).
- `openldap.replicaCount` is the INITIAL count on first install; when
  the HPA is enabled it owns the count afterwards. Keep
  `replicaCount == hpa.minReplicas` so `helm upgrade` doesn't briefly
  scale down before the HPA rescales.

## How full-auto reconcile works

Each writable / RO StatefulSet pod carries a `checksum/topology`
annotation on its PodTemplateSpec, hashed from every input that shapes
`cn=config`'s peer topology:

```
mode | NODE_ROLE | REPLICA_COUNT | serverIdBase | readOnlyServerIdBase
     | externalPeers | suffix
```

Any change to those inputs (bumping `replicaCount`, HPA scaling event,
external peer added) changes the checksum → StatefulSet controller
performs a rolling restart.

On each pod boot:

- `initContainer:bootstrap` computes the desired hash from env vars.
- If the local `${SLAPD_D}/.topology-hash` matches → skip (fast path).
- If not → wipe `${SLAPD_D}` only (data at `${MDB_DIR}` untouched),
  regenerate `cn=config` LDIF with the new peer list, `slapadd -n 0`.
- Success marker + new hash written LAST so a mid-write crash forces
  another reconcile on next boot.

The declarative `overlays` / `acls` / `treeGrants` / `ppolicy` / `users`
/ `groups` sync Jobs run as post-install/upgrade hooks and re-apply
everything they own on every upgrade, so any live cn=config edits they
manage are restored automatically after the reconcile wipe.

## Manual scaling

```bash
helm upgrade ldap kubernetes/charts/openldap-stack \
  --namespace ldap --reuse-values \
  --set openldap.replicaCount=5
```

StatefulSet spins up pods 3 and 4, rolls pods 0-2. Every pod ends the
upgrade knowing about all 5 peers. No `kubectl rollout restart` needed.

Scale down works the same way — bump `replicaCount` down, extra pods
are terminated by K8s (PVCs retained by default so scale-back is fast).

## HPA — resource + custom metrics

```yaml
openldap:
  mode: multi-master
  replicaCount: 2        # initial + hpa.minReplicas

  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 6

    # metrics[] is the autoscaling/v2 spec verbatim.
    metrics:
      # Resource metrics (metrics-server must be present).
      - type: Resource
        resource:
          name: cpu
          target: { type: Utilization, averageUtilization: 70 }
      - type: Resource
        resource:
          name: memory
          target: { type: Utilization, averageUtilization: 80 }

    behavior:
      scaleDown:
        stabilizationWindowSeconds: 600     # 10-minute grace period
        policies:
          - type: Pods
            value: 1
            periodSeconds: 300
      scaleUp:
        stabilizationWindowSeconds: 30
        policies:
          - type: Pods
            value: 2
            periodSeconds: 60
```

### Prometheus-backed custom metrics

`openldap.monitoring.enabled: true` runs the
[`openldap_prometheus_exporter`](https://github.com/maximewewer/openldap_prometheus_exporter)
sidecar and (optionally) a `ServiceMonitor` for prometheus-operator.
To scale on those metrics, you need **prometheus-adapter** (or
**KEDA**) in the cluster — it translates Prometheus queries into the
K8s custom / external metrics API that HPA consumes.

Example — scale up when the per-pod bind rate exceeds 200/s or search
p99 latency crosses 50 ms:

```yaml
openldap:
  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 8
    metrics:
      # CPU floor safety net (metrics-server).
      - type: Resource
        resource:
          name: cpu
          target: { type: Utilization, averageUtilization: 75 }
      # Prometheus-adapter — Pods metric (per-pod scalar).
      - type: Pods
        pods:
          metric:
            name: openldap_bind_rate_per_second
          target:
            type: AverageValue
            averageValue: "200"
      # Prometheus-adapter — Object metric (query against a Service).
      - type: Object
        object:
          describedObject:
            apiVersion: v1
            kind: Service
            name: ldap-openldap
          metric:
            name: openldap_search_p99_ms
          target:
            type: Value
            value: "50"
```

Corresponding **prometheus-adapter rules** (installed alongside the
adapter — outside the chart's scope, kept here as reference):

```yaml
rules:
  - seriesQuery: 'openldap_bind_total{namespace!="",pod!=""}'
    resources:
      overrides:
        namespace: { resource: namespace }
        pod:       { resource: pod }
    name:
      matches: "^openldap_bind_total$"
      as:      "openldap_bind_rate_per_second"
    metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'
```

**KEDA alternative** — install the KEDA operator, then use its
`ScaledObject` CRD instead of the native HPA (heavier dep, but supports
event-driven triggers Prometheus HPA can't do: pub/sub queue depth,
webhook, scheduled scaling with built-in cron trigger).

## Time-of-day scaling — `scaleSchedule`

Chart-native (no KEDA/CronScaler required): each entry emits one
`CronJob` that runs `kubectl patch hpa` at its schedule to adjust the
HPA's min/max window. Perfect for a business-hour ramp-up + off-hour
cooldown when your workload has predictable daily peaks.

```yaml
openldap:
  hpa:
    enabled: true
    minReplicas: 2      # baseline (off-hours default)
    maxReplicas: 3

  scaleSchedule:
    - name: business-hours
      schedule: "0 8 * * 1-5"        # weekdays 08:00 UTC
      minReplicas: 4
      maxReplicas: 8
    - name: off-hours
      schedule: "0 20 * * 1-5"       # weekdays 20:00 UTC
      minReplicas: 2
      maxReplicas: 3
    - name: weekend
      schedule: "0 0 * * 6"          # Saturday 00:00 UTC
      minReplicas: 2
      maxReplicas: 2
    # Optional per-entry timezone (K8s 1.27+ with feature-gate
    # CronJobTimeZone GA in 1.27):
    #   timeZone: "Europe/Paris"
```

Each CronJob runs one `bitnami/kubectl` container (pinned to the same
version as `openldap.cli.kubectlVersion` for consistency), patches
the HPA object, and exits. The sync ServiceAccount is granted the
`autoscaling/horizontalpodautoscalers` verbs `get, patch` when
`scaleSchedule` is set.

**No conflict with the HPA itself** — the CronJob only sets the
min/max window; the HPA still owns the current replica count via its
metrics loop. When `minReplicas` bumps up, the HPA scales up on its
next control loop (~15 s); when it drops down, the `behavior.scaleDown`
stabilization window applies.

## Interaction with PodDisruptionBudget

The chart emits a PDB when `replicaCount > 1` with
`minAvailable = replicaCount - 1`. When the HPA drives the count up,
`minAvailable` stays computed against `replicaCount` — that's the value
at helm render time, NOT the live scale. If you want the PDB to track
the HPA range, override `podDisruptionBudget.minAvailable` with a fixed
value (e.g. `minAvailable: "50%"`).

## PVC lifecycle on scale-down

StatefulSet retention policy defaults to keeping PVCs when pods are
removed (K8s `whenScaled: Retain`). Practical effect:

- Scale 3 → 2: pod-2 terminates, PVC-2 stays.
- Scale back 2 → 3: pod-2 re-attaches its retained PVC and skips seed
  (data still in `${MDB_DIR}`); reconcile branch rebuilds `cn=config`
  with the new topology and joins syncrepl.

To reclaim disk on permanent scale-down, delete the orphan PVCs
manually. If you want automatic cleanup, set
`persistentVolumeClaimRetentionPolicy.whenScaled: Delete` on the
StatefulSet (add via `openldap.extraDeploy` patch — not yet a
first-class chart knob).

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Pods rebooted but `olcSyncRepl` still points at old peers | Look at initContainer logs — should show `Topology changed` line. If not, `checksum/topology` didn't flip; check `helm get manifest` diff. |
| New pod stuck in Init | initContainer log — likely LDIF template error (e.g. schema mismatch). Fall back: delete PVC on the stuck pod, let it seed fresh from ordinal-0. |
| HPA shows `<unknown>` for a Prometheus metric | prometheus-adapter not scraping / metric name mismatch. `kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1` should list your metric. |
| CronJob scaler patched HPA but replicas didn't change | HPA needs a metrics-server reading to react. Wait one control loop (~15 s) or check HPA events for `FailedGetResourceMetric`. |
| Scale-down leaves noisy syncrepl retries in slapd logs | Expected briefly (~1-2 s) while the terminating pod finishes shutdown. Persistent errors after 1 min mean the reconcile didn't run — check initContainer logs on the surviving pods. |
