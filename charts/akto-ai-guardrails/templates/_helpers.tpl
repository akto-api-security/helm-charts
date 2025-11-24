{{/*
Expand the name of the chart.
*/}}
{{- define "akto-ai-guardrails.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "akto-ai-guardrails.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "akto-ai-guardrails.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "akto-ai-guardrails.labels" -}}
helm.sh/chart: {{ include "akto-ai-guardrails.chart" . }}
{{ include "akto-ai-guardrails.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akto-ai-guardrails.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akto-ai-guardrails.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "akto-ai-guardrails.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "akto-ai-guardrails.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Agent Guard Engine labels
*/}}
{{- define "akto-ai-guardrails.agentGuardEngine.labels" -}}
{{ include "akto-ai-guardrails.labels" . }}
app.kubernetes.io/component: agent-guard-engine
{{- end }}

{{/*
Agent Guard Engine selector labels
*/}}
{{- define "akto-ai-guardrails.agentGuardEngine.selectorLabels" -}}
{{ include "akto-ai-guardrails.selectorLabels" . }}
app.kubernetes.io/component: agent-guard-engine
{{- end }}

{{/*
Agent Guard Executor labels
*/}}
{{- define "akto-ai-guardrails.agentGuardExecutor.labels" -}}
{{ include "akto-ai-guardrails.labels" . }}
app.kubernetes.io/component: agent-guard-executor
{{- end }}

{{/*
Agent Guard Executor selector labels
*/}}
{{- define "akto-ai-guardrails.agentGuardExecutor.selectorLabels" -}}
{{ include "akto-ai-guardrails.selectorLabels" . }}
app.kubernetes.io/component: agent-guard-executor
{{- end }}

{{/*
Guardrails Service labels
*/}}
{{- define "akto-ai-guardrails.guardrailsService.labels" -}}
{{ include "akto-ai-guardrails.labels" . }}
app.kubernetes.io/component: guardrails-service
{{- end }}

{{/*
Guardrails Service selector labels
*/}}
{{- define "akto-ai-guardrails.guardrailsService.selectorLabels" -}}
{{ include "akto-ai-guardrails.selectorLabels" . }}
app.kubernetes.io/component: guardrails-service
{{- end }}
