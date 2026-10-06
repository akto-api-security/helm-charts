{{/*
Expand the name of the chart.
*/}}
{{- define "akto.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "akto.fullname" -}}
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
{{- define "akto.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "akto.labels" -}}
helm.sh/chart: {{ include "akto.chart" . }}
{{ include "akto.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akto.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akto.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "akto.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "akto.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
One LLM credential env var for agent-testing. Reads from existingSecret when
given, else from the chart's own agent-testing Secret. Emits nothing when the
credential is unset, so unused providers add no env.
Args: (list envName inlineValue existingSecret secretKey fallbackSecretName)
*/}}
{{- define "akto.agentTesting.credEnv" -}}
{{- $envName := index . 0 -}}
{{- $inline := index . 1 -}}
{{- $existing := index . 2 -}}
{{- $key := index . 3 -}}
{{- $fallback := index . 4 -}}
{{- if or $inline $existing }}
- name: {{ $envName }}
  valueFrom:
    secretKeyRef:
      name: {{ $existing | default $fallback }}
      key: {{ $key }}
{{- end }}
{{- end }}

{{/*
True when any agent-testing LLM credential is set inline, i.e. the chart needs
to create its own Secret.
*/}}
{{- define "akto.agentTesting.needsSecret" -}}
{{- $llm := .Values.testing.agentTesting.env.llm -}}
{{- $env := .Values.testing.agentTesting.env -}}
{{- $legacy := and $env.useSecretsForAnthropicApiKey (not $env.anthropicApiKeySecrets.existingSecret) $env.anthropicApiKeySecrets.anthropicSecretKey -}}
{{- if or (and $llm.azure.apiKey (not $llm.azure.existingSecret))
          (and $llm.vertex.credentialsJson (not $llm.vertex.existingSecret))
          (and $llm.anthropic.apiKey (not $llm.anthropic.existingSecret))
          (and $llm.bedrock.bearerToken (not $llm.bedrock.existingSecret))
          (and $legacy (not (include "akto.agentTesting.anthropicMigrated" .))) -}}
true
{{- end -}}
{{- end }}

{{/*
Non-empty when the new llm.anthropic.* keys are in use, so the deprecated
anthropicApiKey / anthropicApiKeySecrets values are ignored.
*/}}
{{- define "akto.agentTesting.anthropicMigrated" -}}
{{- $a := .Values.testing.agentTesting.env.llm.anthropic -}}
{{- if or $a.apiKey $a.existingSecret -}}
true
{{- end -}}
{{- end }}

{{/*
ANTHROPIC_API_KEY, honouring the deprecated anthropicApiKey /
anthropicApiKeySecrets values when llm.anthropic.* is unset. The legacy paths
keep their old behaviour exactly, including the plaintext one.
*/}}
{{- define "akto.agentTesting.anthropicEnv" -}}
{{- $env := .Values.testing.agentTesting.env -}}
{{- $a := $env.llm.anthropic -}}
{{- $fallback := printf "%s-agent-testing" (include "akto.fullname" .) -}}
{{- if include "akto.agentTesting.anthropicMigrated" . }}
{{- include "akto.agentTesting.credEnv" (list "ANTHROPIC_API_KEY" $a.apiKey $a.existingSecret $a.existingSecretKey $fallback) }}
{{- else if $env.useSecretsForAnthropicApiKey }}
- name: ANTHROPIC_API_KEY
  valueFrom:
    secretKeyRef:
      key: token
      name: {{ (tpl $env.anthropicApiKeySecrets.existingSecret .) | default $fallback }}
{{- else if $env.anthropicApiKey }}
- name: ANTHROPIC_API_KEY
  value: {{ quote $env.anthropicApiKey }}
{{- end }}
{{- end }}
