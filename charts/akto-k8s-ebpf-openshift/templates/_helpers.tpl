{{- define "akto-k8s-ebpf-openshift.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "akto-k8s-ebpf-openshift.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "akto-k8s-ebpf-openshift.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "akto-k8s-ebpf-openshift.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "akto-k8s-ebpf-openshift.sccClusterRoleBindingName" -}}
{{- printf "%s-%s-scc-use" .Release.Name (include "akto-k8s-ebpf-openshift.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "akto-k8s-ebpf-openshift.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akto-k8s-ebpf-openshift.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
