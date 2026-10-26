{{/* Chart name */}}
{{- define "agentos.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name */}}
{{- define "agentos.fullname" -}}
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

{{/* Database resources name */}}
{{- define "agentos.dbFullname" -}}
{{- printf "%s-db" (include "agentos.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels */}}
{{- define "agentos.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "agentos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels — the component key keeps the api and database
     workloads from matching each other's Services. */}}
{{- define "agentos.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agentos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: server
{{- end -}}

{{- define "agentos.dbSelectorLabels" -}}
app.kubernetes.io/name: {{ include "agentos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end -}}

{{/* App secret name */}}
{{- define "agentos.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- include "agentos.fullname" . -}}
{{- end -}}
{{- end -}}

{{/* Database secret name */}}
{{- define "agentos.dbSecretName" -}}
{{- if .Values.postgres.enabled -}}
{{- default (include "agentos.dbFullname" .) .Values.postgres.auth.existingSecret -}}
{{- else -}}
{{- default (include "agentos.dbFullname" .) .Values.externalDatabase.existingSecret -}}
{{- end -}}
{{- end -}}

{{/* Database connection facts */}}
{{- define "agentos.dbHost" -}}
{{- if .Values.postgres.enabled -}}
{{- include "agentos.dbFullname" . -}}
{{- else -}}
{{- required "externalDatabase.host is required when postgres.enabled=false" .Values.externalDatabase.host -}}
{{- end -}}
{{- end -}}

{{- define "agentos.dbPort" -}}
{{- if .Values.postgres.enabled -}}5432{{- else -}}{{ .Values.externalDatabase.port }}{{- end -}}
{{- end -}}

{{- define "agentos.dbUser" -}}
{{- if .Values.postgres.enabled -}}{{ .Values.postgres.auth.username }}{{- else -}}{{ .Values.externalDatabase.username }}{{- end -}}
{{- end -}}

{{- define "agentos.dbDatabase" -}}
{{- if .Values.postgres.enabled -}}{{ .Values.postgres.auth.database }}{{- else -}}{{ .Values.externalDatabase.database }}{{- end -}}
{{- end -}}

{{/* Scheduler base URL: explicit value > public ingress URL > in-cluster
     service DNS (reachable out of the box — cron triggers stay inside the
     cluster). Left pointing at localhost, scheduled jobs silently never
     fire; this helper makes that state unrepresentable. */}}
{{- define "agentos.agentosUrl" -}}
{{- if .Values.agentosUrl -}}
{{- .Values.agentosUrl -}}
{{- else if and .Values.ingress.enabled .Values.ingress.host -}}
{{- printf "https://%s" .Values.ingress.host -}}
{{- else -}}
{{- printf "http://%s:%v" (include "agentos.fullname" .) .Values.service.port -}}
{{- end -}}
{{- end -}}
