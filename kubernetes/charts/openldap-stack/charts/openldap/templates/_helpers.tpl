{{/*
Expand the name of the chart.
*/}}
{{- define "openldap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name — <release>-<chart> unless the release already
carries the chart name (avoids ldap-openldap when release is "openldap").
*/}}
{{- define "openldap.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart-name label value.
*/}}
{{- define "openldap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard label set — recommended labels + Helm meta.
*/}}
{{- define "openldap.labels" -}}
helm.sh/chart: {{ include "openldap.chart" . }}
{{ include "openldap.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: openldap-stack
{{- with .Values.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels — stable subset used in Service selectors and StatefulSet.
*/}}
{{- define "openldap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openldap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "openldap.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "openldap.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Admin Secret name — either an override (existingSecret) or the chart-managed
`<fullname>-admin` Secret. Never write into the user-managed Secret.
*/}}
{{- define "openldap.adminSecretName" -}}
{{- if .Values.admin.existingSecret -}}
{{- .Values.admin.existingSecret -}}
{{- else -}}
{{- printf "%s-admin" (include "openldap.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return an existing password from a lookup, or generate a fresh one. Called
from the Secret template so passwords are stable across `helm upgrade` even
though random funcs re-roll on every render.
    _ := include "openldap.persistedPassword" (dict "context" . "secretName" X "key" Y "len" 32)
*/}}
{{- define "openldap.persistedPassword" -}}
{{- $ctx := .context -}}
{{- $existing := lookup "v1" "Secret" $ctx.Release.Namespace .secretName -}}
{{- if and $existing (index $existing.data .key) -}}
{{- index $existing.data .key | b64dec -}}
{{- else -}}
{{- randAlphaNum (default 32 .len) -}}
{{- end -}}
{{- end -}}

{{/*
Headless service DNS name (for peer discovery in HA modes).
*/}}
{{- define "openldap.headlessServiceName" -}}
{{- printf "%s-headless" (include "openldap.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Replicator Secret name — either an override (existingSecret) or the chart-
managed `<fullname>-replicator` Secret with a persisted random password.
*/}}
{{- define "openldap.replicatorSecretName" -}}
{{- if .Values.replication.replicator.existingSecret -}}
{{- .Values.replication.replicator.existingSecret -}}
{{- else -}}
{{- printf "%s-replicator" (include "openldap.fullname" .) -}}
{{- end -}}
{{- end -}}
