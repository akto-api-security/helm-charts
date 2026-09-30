{{- define "akto-regional-setup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "akto-regional-setup.fullname" -}}
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

{{- define "akto-regional-setup.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Usage: {{ include "akto-regional-setup.componentName" (list . "mini-runtime") }}
*/}}
{{- define "akto-regional-setup.componentName" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{- printf "%s-%s" (include "akto-regional-setup.fullname" $ctx) $component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "akto-regional-setup.labels" -}}
helm.sh/chart: {{ include "akto-regional-setup.chart" . }}
{{ include "akto-regional-setup.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: akto
{{- end }}

{{- define "akto-regional-setup.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akto-regional-setup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "akto-regional-setup.componentLabels" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{ include "akto-regional-setup.labels" $ctx }}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{- define "akto-regional-setup.componentSelectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{ include "akto-regional-setup.selectorLabels" $ctx }}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{- define "akto-regional-setup.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "akto-regional-setup.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Agent-guard's own ServiceAccount, so an IAM role for model access (Bedrock via
IRSA / EKS Pod Identity) is granted to agent-guard alone rather than to every
component sharing the release ServiceAccount. Falls back to that shared one
when agentGuard.serviceAccount is neither created nor named.
*/}}
{{- define "akto-regional-setup.agentGuard.serviceAccountName" -}}
{{- $sa := .Values.agentGuard.serviceAccount | default dict }}
{{- if $sa.create }}
{{- default (include "akto-regional-setup.componentName" (list . "agent-guard")) $sa.name }}
{{- else if $sa.name }}
{{- $sa.name }}
{{- else }}
{{- include "akto-regional-setup.serviceAccountName" . }}
{{- end }}
{{- end }}

{{/*
Renders "repository@digest" when a digest is set, else "repository:tag".
Usage: {{ include "akto-regional-setup.image" .Values.miniRuntime.image }}
*/}}
{{- define "akto-regional-setup.image" -}}
{{- if .digest -}}
{{ .repository }}@{{ .digest }}
{{- else -}}
{{ .repository }}:{{ .tag | default "latest" }}
{{- end -}}
{{- end }}

{{/*
------------------------------------------------------------------------------
Central cloud endpoints.

These replace the per-component URL values the old charts each had, so an
operator sets the central address once instead of six times.
------------------------------------------------------------------------------
*/}}

{{- define "akto-regional-setup.central.databaseAbstractorUrl" -}}
{{- .Values.central.databaseAbstractorUrl | default "https://cyborg.akto.io" -}}
{{- end }}

{{- define "akto-regional-setup.central.threatBackendUrl" -}}
{{- .Values.central.threatBackendUrl | default "https://tbs.akto.io" -}}
{{- end }}

{{/*
Full URL guardrails POSTs blocked/malicious events to.
*/}}
{{- define "akto-regional-setup.central.threatDetectionApiUrl" -}}
{{- printf "%s/api/threat_detection/record_malicious_event" (trimSuffix "/" (include "akto-regional-setup.central.threatBackendUrl" .)) -}}
{{- end }}

{{/*
------------------------------------------------------------------------------
Azure Key Vault. The default source of every secret in this chart: each pod
that reads one also mounts the CSI volume below, because the Azure Key Vault
provider only syncs a SecretProviderClass into its Kubernetes Secret when
something actually mounts it, so at least one consumer per release has to.

Setting global.keyVault.enabled=false emits neither the volume nor its mounts,
for clusters that have no secrets-store CSI driver at all. Nothing else
changes: every credential is still read with a secretKeyRef against the Secret
named by global.keyVault.secretName, which you then create yourself. The
secretKeyRef does not care what wrote that Secret.
------------------------------------------------------------------------------
*/}}
{{- define "akto-regional-setup.keyVault.volumeMounts" -}}
{{- if .Values.global.keyVault.enabled -}}
- name: secrets-store
  mountPath: /mnt/secrets-store
  readOnly: true
{{- end }}
{{- end }}

{{- define "akto-regional-setup.keyVault.volumes" -}}
{{- if .Values.global.keyVault.enabled -}}
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ .Values.global.keyVault.secretProviderClass }}
{{- end }}
{{- end }}

{{/*
Just the valueFrom block for the central database-abstractor token, reused
wherever the env var name differs (threat-client also authenticates to the
threat backend with the same token, under a different env var name).
*/}}
{{- define "akto-regional-setup.central.tokenSecretKeyRef" -}}
valueFrom:
  secretKeyRef:
    name: {{ .Values.global.keyVault.secretName }}
    key: {{ .Values.central.databaseAbstractorTokenKey | default "databaseAbstractorToken" }}
{{- end }}

{{/*
DATABASE_ABSTRACTOR_SERVICE_TOKEN, always via secretKeyRef so the token never
appears in a Deployment spec.
*/}}
{{- define "akto-regional-setup.central.tokenEnv" -}}
- name: DATABASE_ABSTRACTOR_SERVICE_TOKEN
  {{- include "akto-regional-setup.central.tokenSecretKeyRef" . | nindent 2 }}
{{- end }}

{{/*
AKTO_DI_REVOKED_TOKENS - optional, so it's fine to leave unsynced.
*/}}
{{- define "akto-regional-setup.dataIngestion.revokedTokensEnv" -}}
- name: AKTO_DI_REVOKED_TOKENS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ .Values.dataIngestion.env.revokedTokensKey | default "diRevokedTokens" }}
      optional: true
{{- end }}

{{/*
Bundled Redis Service address (host:port only, no scheme/credentials).
*/}}
{{- define "akto-regional-setup.guardrailsRedis.host" -}}
{{- printf "%s:%v" (include "akto-regional-setup.svcHost" (list . "guardrails-redis")) .Values.guardrailsRedis.service.port -}}
{{- end }}

{{/*
REDIS_URL for the guardrails semantic cache.

- guardrailsRedis.enabled=true: auto-targets the bundled Redis in this
  release. The password is REQUIRED (not optional) here on purpose: Kubernetes
  leaves a $(VAR) reference in command/args and env value fields UNCHANGED,
  as a literal string, when the referenced env var is undefined - it does
  NOT resolve to an empty string. An optional/missing key would silently make
  Redis require the literal password "$(REDIS_PASSWORD)" while this env var
  composes the literal "$(GUARDRAILS_REDIS_PASSWORD)" instead - two different
  literal strings, so the cache would silently fail to authenticate rather
  than cleanly run passwordless. Sync a real password before enabling this.
- guardrailsRedis.enabled=false: reads a full connection string for an
  EXTERNAL Redis from Key Vault instead. Optional - an unsynced/missing key
  leaves REDIS_URL unset entirely, same as today's "leave it blank" behavior
  (cache stays off, fail-open).
*/}}
{{- define "akto-regional-setup.guardrailsService.redisEnv" -}}
{{- if .Values.guardrailsRedis.enabled }}
- name: GUARDRAILS_REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ .Values.guardrailsRedis.passwordKey | default "guardrailsRedisPassword" }}
- name: REDIS_URL
  value: {{ printf "redis://:$(GUARDRAILS_REDIS_PASSWORD)@%s" (include "akto-regional-setup.guardrailsRedis.host" .) | quote }}
{{- else }}
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ .Values.guardrailsService.env.redisUrlKey | default "guardrailsRedisUrl" }}
      optional: true
{{- end }}
{{- end }}

{{/*
Agent-guard's model-provider credentials - the actual secret material only
(API keys, service-account key JSON). Every key is optional: fill in only the
provider(s) you actually use by syncing that key into Key Vault, leave the
rest unsynced. (env var name, Key Vault key name) pairs.
*/}}
{{- define "akto-regional-setup.agentGuard.secretEnv" -}}
{{- $pairs := list
  (list "VERTEX_AI_SA_KEY_JSON" "vertexAiSaKeyJson")
  (list "QWEN3GUARD_SA_KEY_JSON" "qwen3guardSaKeyJson")
  (list "GEMMA_VERTEX_SA_KEY_JSON" "gemmaVertexSaKeyJson")
  (list "QWEN3GUARD_FOUNDRY_API_KEY" "qwen3guardFoundryApiKey")
  (list "GEMMA_FOUNDRY_API_KEY" "gemmaFoundryApiKey")
  (list "AZURE_FOUNDRY_API_KEY" "azureFoundryApiKey")
  (list "ANTHROPIC_FOUNDRY_API_KEY" "anthropicFoundryApiKey")
  (list "ANTHROPIC_API_KEY" "anthropicApiKey")
  (list "OPENAI_API_KEY" "openaiApiKey")
-}}
{{- range $pairs }}
- name: {{ index . 0 }}
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.global.keyVault.secretName }}
      key: {{ index . 1 }}
      optional: true
{{- end }}
{{- end }}

{{/*
Agent-guard's model-provider config - everything that isn't a credential:
base URLs, deployment/model names, project/location/endpoint identifiers,
dedicated-DNS hosts, and the provider-routing JSON. Plain values, not Key
Vault. (env var name, agentGuard.env key name) pairs.
*/}}
{{- define "akto-regional-setup.agentGuard.providerEnv" -}}
{{- $pairs := list
  (list "VERTEX_AI_PROJECT" "vertexAiProject")
  (list "VERTEX_AI_LOCATION" "vertexAiLocation")
  (list "VERTEX_AI_ENDPOINT_ID" "vertexAiEndpointId")
  (list "QWEN3GUARD_PROJECT" "qwen3guardProject")
  (list "QWEN3GUARD_LOCATION" "qwen3guardLocation")
  (list "QWEN3GUARD_ENDPOINT_ID" "qwen3guardEndpointId")
  (list "QWEN3GUARD_DEDICATED_DNS" "qwen3guardDedicatedDns")
  (list "GEMMA_VERTEX_PROJECT" "gemmaVertexProject")
  (list "GEMMA_VERTEX_LOCATION" "gemmaVertexLocation")
  (list "GEMMA_VERTEX_ENDPOINT_ID" "gemmaVertexEndpointId")
  (list "GEMMA_VERTEX_DEDICATED_DNS" "gemmaVertexDedicatedDns")
  (list "QWEN3GUARD_FOUNDRY_BASE_URL" "qwen3guardFoundryBaseUrl")
  (list "QWEN3GUARD_FOUNDRY_DEPLOYMENT" "qwen3guardFoundryDeployment")
  (list "QWEN3GUARD_FOUNDRY_MODEL" "qwen3guardFoundryModel")
  (list "GEMMA_FOUNDRY_BASE_URL" "gemmaFoundryBaseUrl")
  (list "GEMMA_FOUNDRY_DEPLOYMENT" "gemmaFoundryDeployment")
  (list "GEMMA_FOUNDRY_MODEL" "gemmaFoundryModel")
  (list "AZURE_FOUNDRY_BASE_URL" "azureFoundryBaseUrl")
  (list "AZURE_FOUNDRY_DEPLOYMENT" "azureFoundryDeployment")
  (list "AZURE_FOUNDRY_MODEL" "azureFoundryModel")
  (list "ANTHROPIC_FOUNDRY_BASE_URL" "anthropicFoundryBaseUrl")
  (list "ANTHROPIC_FOUNDRY_DEPLOYMENT" "anthropicFoundryDeployment")
  (list "ANTHROPIC_FOUNDRY_MODEL" "anthropicFoundryModel")
  (list "ANTHROPIC_MODEL" "anthropicModel")
  (list "OPENAI_MODEL" "openaiModel")
  (list "OPENAI_COMPATIBLE_BASE_URL" "openaiCompatibleBaseUrl")
  (list "BEDROCK_REGION" "bedrockRegion")
  (list "BEDROCK_MODEL" "bedrockModel")
  (list "DEFAULT_MODEL_CONFIG_JSON" "defaultModelConfigJson")
-}}
{{- range $pairs }}
{{- $val := index $.Values.agentGuard.env (index . 1) }}
{{- if $val }}
- name: {{ index . 0 }}
  value: {{ quote $val }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Env every Akto JVM component shares.
*/}}
{{- define "akto-regional-setup.commonEnv" -}}
- name: IS_KUBERNETES
  value: "true"
- name: AKTO_ACCOUNT_NAME
  value: {{ quote .Values.global.accountName }}
- name: AKTO_CONFIG_NAME
  value: {{ quote .Values.global.configName }}
- name: AKTO_LOG_LEVEL
  value: {{ quote .Values.global.aktoLogLevel }}
- name: KUBERNETES_CLUSTER_DOMAIN
  value: {{ quote .Values.global.kubernetesClusterDomain }}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
{{- end }}

{{/*
------------------------------------------------------------------------------
In-cluster service URLs. Every component that needs a sibling resolves it here
rather than expecting the operator to paste an FQDN.
------------------------------------------------------------------------------
*/}}

{{- define "akto-regional-setup.svcHost" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{- printf "%s.%s.svc.%s" (include "akto-regional-setup.componentName" (list $ctx $component)) $ctx.Release.Namespace $ctx.Values.global.kubernetesClusterDomain -}}
{{- end }}

{{- define "akto-regional-setup.miniRuntime.kafkaUrl" -}}
{{- if .Values.miniRuntime.external.enabled -}}
{{- required "miniRuntime.external.brokerUrl is required when miniRuntime.external.enabled=true" .Values.miniRuntime.external.brokerUrl -}}
{{- else -}}
{{- printf "%s:%v" (include "akto-regional-setup.svcHost" (list . "mini-runtime")) .Values.miniRuntime.service.kafkaPort -}}
{{- end -}}
{{- end }}

{{- define "akto-regional-setup.guardrailsKafka.url" -}}
{{- printf "%s:%v" (include "akto-regional-setup.svcHost" (list . "guardrails-kafka")) .Values.guardrailsKafka.service.kafkaPort -}}
{{- end }}

{{- define "akto-regional-setup.agentGuard.url" -}}
{{- printf "http://%s:%v" (include "akto-regional-setup.svcHost" (list . "agent-guard")) .Values.agentGuard.service.port -}}
{{- end }}

{{- define "akto-regional-setup.anonymizer.url" -}}
{{- printf "http://%s:%v" (include "akto-regional-setup.svcHost" (list . "anonymizer")) .Values.anonymizer.service.port -}}
{{- end }}

{{- define "akto-regional-setup.embedder.url" -}}
{{- printf "http://%s:%v" (include "akto-regional-setup.svcHost" (list . "embedder")) .Values.embedder.service.port -}}
{{- end }}

{{- define "akto-regional-setup.guardrailsService.url" -}}
{{- printf "http://%s:%v" (include "akto-regional-setup.svcHost" (list . "guardrails-service-http")) .Values.guardrailsService.http.service.port -}}
{{- end }}

{{/*
Kafka the mini-runtime process itself uses: its own bundled broker over
localhost, or the configured external cluster.
*/}}
{{- define "akto-regional-setup.miniRuntime.brokerForRuntime" -}}
{{- if .Values.miniRuntime.external.enabled -}}
{{- required "miniRuntime.external.brokerUrl is required when miniRuntime.external.enabled=true" .Values.miniRuntime.external.brokerUrl -}}
{{- else -}}
localhost:29092
{{- end -}}
{{- end }}

{{/*
Kafka the threat client consumes traffic from. Explicit override wins; then the
mini-runtime broker in this release; else its own bundled broker.
*/}}
{{- define "akto-regional-setup.threatClient.trafficBroker" -}}
{{- if .Values.threatClient.external.enabled -}}
{{- if .Values.threatClient.external.brokerUrl -}}
{{- .Values.threatClient.external.brokerUrl -}}
{{- else if .Values.miniRuntime.enabled -}}
{{- include "akto-regional-setup.miniRuntime.kafkaUrl" . -}}
{{- else -}}
{{- fail "threatClient.external.enabled=true but no brokerUrl given and miniRuntime is disabled - set threatClient.external.brokerUrl" -}}
{{- end -}}
{{- else -}}
localhost:29092
{{- end -}}
{{- end }}

{{/*
Kafka the data ingestion service produces into.
*/}}
{{- define "akto-regional-setup.dataIngestion.brokerUrl" -}}
{{- if .Values.dataIngestion.env.kafkaBrokerUrl -}}
{{- .Values.dataIngestion.env.kafkaBrokerUrl -}}
{{- else if .Values.miniRuntime.enabled -}}
{{- include "akto-regional-setup.miniRuntime.kafkaUrl" . -}}
{{- else -}}
{{- fail "dataIngestion.env.kafkaBrokerUrl must be set when miniRuntime.enabled=false" -}}
{{- end -}}
{{- end }}

{{/*
Guardrails service URL the ingestion service calls when guardrails is on.
*/}}
{{- define "akto-regional-setup.dataIngestion.guardrailsUrl" -}}
{{- if .Values.dataIngestion.env.guardrailsServiceUrl -}}
{{- .Values.dataIngestion.env.guardrailsServiceUrl -}}
{{- else if .Values.guardrailsService.http.enabled -}}
{{- include "akto-regional-setup.guardrailsService.url" . -}}
{{- end -}}
{{- end }}

{{- define "akto-regional-setup.dataIngestion.url" -}}
{{- printf "http://%s:%v" (include "akto-regional-setup.svcHost" (list . "data-ingestion")) .Values.dataIngestion.service.port -}}
{{- end }}

{{/*
Data-ingestion URL the lambda egress proxy forwards to.
*/}}
{{- define "akto-regional-setup.lambdaEgressProxy.validateUrl" -}}
{{- if .Values.lambdaEgressProxy.env.dataIngestionServiceUrl -}}
{{- .Values.lambdaEgressProxy.env.dataIngestionServiceUrl -}}
{{- else if .Values.dataIngestion.enabled -}}
{{- printf "%s%s" (include "akto-regional-setup.dataIngestion.url" .) (.Values.lambdaEgressProxy.env.validatePath | default "/api/http-proxy") -}}
{{- else -}}
{{- fail "lambdaEgressProxy.env.dataIngestionServiceUrl must be set when dataIngestion.enabled=false" -}}
{{- end -}}
{{- end }}

{{/*
AKTO_AUTHORIZATION - the shared token the Lambda sends to the proxy on each
call, forwarded through to data-ingestion/guardrails downstream.
*/}}
{{- define "akto-regional-setup.lambdaEgressProxy.authorizationEnv" -}}
- name: AKTO_AUTHORIZATION
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ .Values.lambdaEgressProxy.env.authorizationTokenKey | default .Values.central.databaseAbstractorTokenKey | default "databaseAbstractorToken" }}
{{- end }}

{{/*
Where guardrails-service sends scan requests.
*/}}
{{- define "akto-regional-setup.guardrails.scannerUrl" -}}
{{- if .Values.guardrailsService.env.scannerApiUrl -}}
{{- .Values.guardrailsService.env.scannerApiUrl -}}
{{- else if .Values.agentGuard.enabled -}}
{{- include "akto-regional-setup.agentGuard.url" . -}}
{{- else -}}
{{- fail "guardrailsService.env.scannerApiUrl must be set when agentGuard.enabled=false" -}}
{{- end -}}
{{- end }}

{{/*
Kafka carrying the malicious-event buffer. Producer and forwarder both resolve
through this helper so they cannot drift apart - a mismatch would be silent.
Not the threat client's own broker: that is a sidecar addressed as localhost.
*/}}
{{/*
Buffer broker as guardrails-service sees it: the forwarder's Service when the
broker is bundled there, or the external cluster.
*/}}
{{- define "akto-regional-setup.threatBuffer.broker" -}}
{{- if .Values.guardrailsThreatBuffer.kafkaBrokerUrl -}}
{{- .Values.guardrailsThreatBuffer.kafkaBrokerUrl -}}
{{- else -}}
{{- printf "%s:%v" (include "akto-regional-setup.svcHost" (list . "guardrails-threat-forwarder")) .Values.guardrailsThreatBuffer.service.kafkaPort -}}
{{- end -}}
{{- end }}

{{/*
Same broker as the forwarder sees it - over loopback when it is the sidecar in
its own pod, so it never round-trips through the Service.
*/}}
{{- define "akto-regional-setup.threatBuffer.brokerForForwarder" -}}
{{- if .Values.guardrailsThreatBuffer.kafkaBrokerUrl -}}
{{- .Values.guardrailsThreatBuffer.kafkaBrokerUrl -}}
{{- else -}}
localhost:29092
{{- end -}}
{{- end }}

{{/*
Kafka the Kafka-mode guardrails service consumes from.
*/}}
{{- define "akto-regional-setup.guardrails.kafkaBroker" -}}
{{- if .Values.guardrailsService.kafka.brokerUrl -}}
{{- .Values.guardrailsService.kafka.brokerUrl -}}
{{- else if .Values.guardrailsKafka.enabled -}}
{{- include "akto-regional-setup.guardrailsKafka.url" . -}}
{{- else if .Values.miniRuntime.enabled -}}
{{- include "akto-regional-setup.miniRuntime.kafkaUrl" . -}}
{{- else -}}
{{- fail "guardrailsService.kafka.brokerUrl must be set when neither guardrailsKafka nor miniRuntime is enabled" -}}
{{- end -}}
{{- end }}

{{/*
Probe block shared by the guardrails components.
Usage: {{ include "akto-regional-setup.probes" (list .Values.agentGuard 8090) }}
*/}}
{{- define "akto-regional-setup.probes" -}}
{{- $c := index . 0 -}}
{{- $port := index . 1 -}}
{{- if $c.livenessProbe.enabled }}
livenessProbe:
  httpGet:
    path: {{ $c.livenessProbe.path }}
    port: {{ $port }}
  initialDelaySeconds: {{ $c.livenessProbe.initialDelaySeconds }}
  periodSeconds: {{ $c.livenessProbe.periodSeconds }}
  timeoutSeconds: {{ $c.livenessProbe.timeoutSeconds }}
  failureThreshold: {{ $c.livenessProbe.failureThreshold }}
{{- end }}
{{- if $c.readinessProbe.enabled }}
readinessProbe:
  httpGet:
    path: {{ $c.readinessProbe.path }}
    port: {{ $port }}
  initialDelaySeconds: {{ $c.readinessProbe.initialDelaySeconds }}
  periodSeconds: {{ $c.readinessProbe.periodSeconds }}
  timeoutSeconds: {{ $c.readinessProbe.timeoutSeconds }}
  failureThreshold: {{ $c.readinessProbe.failureThreshold }}
{{- end }}
{{- end }}

{{/*
Pod-level scheduling block, identical for every component.
*/}}
{{- define "akto-regional-setup.scheduling" -}}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
