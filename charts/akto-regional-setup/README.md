# Akto Regional Cloud

One chart for everything that runs at the edge:

| Component | What it does | Default |
|---|---|---|
| `mini-runtime` | Parses mirrored traffic; hosts the traffic Kafka bus | on |
| `threat-client` | Detects malicious traffic, reports to central | on |
| `data-ingestion` | HTTP front door traffic is posted to | on |
| `lambda-egress-proxy` | mitmproxy forward proxy an external AWS Lambda routes egress through; forwards to data-ingestion. See [docs/lambda-egress-proxy.md](docs/lambda-egress-proxy.md) | off |
| `guardrails-service` (http) | AI guardrails entrypoint | on |
| `agent-guard` | Runs the guardrail scanners | on |
| `anonymizer` | PII masking used by agent-guard | on |
| `guardrails-service` (kafka) | Kafka-consumer flavour of guardrails | on |
| `guardrails-kafka` | Dedicated broker for the above | off |
| `embedder` | Semantic-cache embeddings | on |
| `guardrails-redis` | Bundled redis-stack-server backing the semantic cache | on |

This replaces installing `akto-mini-runtime`, `akto-threat-client`,
`data-ingestion-service` and `akto-ai-guardrails-v2` separately and then
hand-wiring six URLs between them and central.

## Install

Every secret this chart needs - the central auth token, and optionally
external-Kafka SASL credentials and agent-guard's model-provider API keys -
is read with a `secretKeyRef` against the Secret named by
`global.keyVault.secretName`. There is no plaintext-token install path.

By default that Secret is synced from Azure Key Vault: create a
SecretProviderClass first that syncs at least a `databaseAbstractorToken` key
into it, then:

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts
helm repo update akto

helm install akto-regional-setup akto/akto-regional-setup -n akto-regional --create-namespace \
  --set central.databaseAbstractorUrl="https://cyborg.example.com" \
  --set central.threatBackendUrl="https://tbs.example.com" \
  --set global.keyVault.secretProviderClass="akto-keyvault"
```

On a cluster with no secrets-store CSI driver, set `global.keyVault.enabled=false`
and create that Secret yourself instead - the `secretKeyRef`s do not care what
wrote it, and no SecretProviderClass is needed:

```bash
kubectl create secret generic akto-secrets -n akto-regional \
  --from-literal=databaseAbstractorToken='<token>' \
  --from-literal=guardrailsRedisPassword='<password>'
```

Get those two URLs from the `akto-central-setup` install notes.

- `threatBackendUrl`: central runs in a different cluster, so use its
  **external** address (its `service.type` can be set to `LoadBalancer`),
  including the port if you expose it directly (e.g. `http://20.75.204.53:9090`).
- `databaseAbstractorUrl`: `database-abstractor` is **ClusterIP only, always**
  on the central side (no public IP, by design). If central and regional
  share one cluster, its ClusterIP DNS name works as-is. If they're separate
  clusters, you need your own private connectivity to it first (VPN, peering,
  a private endpoint) — not something either chart sets up.

Verify:

```bash
kubectl get pods -n akto-regional -l app.kubernetes.io/instance=akto-regional-setup
```

`mini-runtime` and `threat-client` are 2/2 — the second container is each one's
Kafka broker.

## Auto-wiring

Everything below is computed by the chart. These are exactly the `--set` flags
and `kubectl set env` commands this chart exists to eliminate:

| Consumer | Variable | Resolved to |
|---|---|---|
| mini-runtime, threat-client, data-ingestion, guardrails, agent-guard | `DATABASE_ABSTRACTOR_SERVICE_URL` | `central.databaseAbstractorUrl` |
| all of the above | `DATABASE_ABSTRACTOR_SERVICE_TOKEN` | the Key Vault-synced Secret, via `secretKeyRef` |
| threat-client | `AKTO_THREAT_PROTECTION_BACKEND_URL` | `central.threatBackendUrl` |
| guardrails | `THREAT_BACKEND_URL` | `central.threatBackendUrl` |
| guardrails | `THREAT_DETECTION_API_URL` | `central.threatBackendUrl` + `/api/threat_detection/record_malicious_event` |
| data-ingestion | `AKTO_KAFKA_BROKER_URL` | the mini-runtime broker in this release |
| data-ingestion | `GUARDRAILS_SERVICE_URL` | the guardrails service in this release |
| mini-runtime | `AKTO_GUARDRAIL_REDACTION_URL` | the guardrails service in this release (base URL, no `/api`); override with `miniRuntime.env.guardrailRedactionUrl` |
| lambda-egress-proxy | `AKTO_VALIDATE_URL` | the data-ingestion service in this release + `lambdaEgressProxy.env.validatePath` (`/api/http-proxy`); override wholesale with `lambdaEgressProxy.env.dataIngestionServiceUrl` |
| lambda-egress-proxy | `AKTO_AUTHORIZATION` | the Key Vault-synced Secret, via `secretKeyRef` - reuses `central.databaseAbstractorTokenKey` unless `lambdaEgressProxy.env.authorizationTokenKey` names its own key |
| guardrails | `SCANNER_API_URL` | agent-guard in this release |
| guardrails | `EMBEDDER_URL` | embedder in this release, when enabled |
| agent-guard | `ANONYMIZER_URL` | anonymizer in this release |
| threat-client | traffic bootstrap servers | its own broker, or mini-runtime's |

The token is never written into a Deployment spec — it's read via `secretKeyRef`
from the same Key Vault-synced Secret every other secret in this chart uses. If
your SecretProviderClass syncs it under a different key name:

```bash
--set central.databaseAbstractorTokenKey=myTokenKeyName
```

Any auto-wired value can still be overridden explicitly, e.g.
`dataIngestion.env.kafkaBrokerUrl`, `guardrailsService.env.scannerApiUrl`.

## Restricting outbound traffic (NetworkPolicy)

**Enabled by default** — same mechanism as `akto-central-setup`: each component gets a
`policyTypes: [Egress]` policy, so outbound is default-deny and only the chart's
rules are allowed.

Allowed by default: DNS, other pods in this release, and
`10.0.0.0/8` + `172.16.0.0/12` + `192.168.0.0/16`.

Two things regional needs that central doesn't:

**1. Central is in another cluster.** If its address is not in private space,
regional cannot reach it. `egressAllowlist` is empty by default and purely
additive to the private ranges above (which are hardcoded, not part of this
list), so index from `[0]`:

```bash
--set 'networkPolicy.egressAllowlist[0].cidr=203.0.113.10/32'
```

**2. Agent Guard calls model providers.** Vertex AI, Azure AI Foundry, OpenAI and
Anthropic are all external. Allowlist them on that component only:

```yaml
networkPolicy:
  components:
    agentGuard:
      egressAllowlist:
        - cidr: 203.0.113.0/24
          ports:
            - port: 443
              protocol: TCP
```

Turn it off with `--set networkPolicy.enabled=false`.

> **Enforcement requires a NetworkPolicy-capable CNI** (Calico, Cilium, Azure
> NPM). On a CNI that ignores NetworkPolicy the objects are created but nothing
> is restricted.

## Common configurations

**Point at an existing Kafka (MSK, Confluent Cloud) instead of the bundled broker:**

Sync the SASL username/password into Key Vault under the keys named by
`miniRuntime.external.usernameKey`/`passwordKey` (defaults:
`miniRuntimeKafkaUsername` / `miniRuntimeKafkaPassword`), then:

```bash
--set miniRuntime.external.enabled=true \
--set miniRuntime.external.brokerUrl="b-1.msk.amazonaws.com:9096" \
--set miniRuntime.external.saslEnabled=true \
--set miniRuntime.external.saslMechanism=SCRAM-SHA-512 \
--set miniRuntime.external.securityProtocol=SASL_SSL
```

**Have the threat client read mini-runtime's bus instead of its own broker:**

```bash
--set threatClient.external.enabled=true
```

Leave `brokerUrl` blank and it targets mini-runtime automatically.

**Guardrails inline on ingested traffic:** on by default. To turn it off:

```bash
--set dataIngestion.env.enableGuardrails=false
```

**Kafka-mode guardrails (`guardrailsService.kafka`) is on by default** - `/api/ingestData` callers can set `publishToGuardrails=true` on their request independent of the HTTP-proxy path, and that flag isn't limited to code in this repo (whatever your real traffic source is may set it). Without a consumer running, those messages would just accumulate unread in the `akto.guardrails` topic. It auto-targets the mini-runtime broker by default - no separate broker needed.

Give it its own dedicated broker instead of sharing mini-runtime's:

```bash
--set guardrailsKafka.enabled=true
```

Turn Kafka-mode off entirely, only if you're certain nothing in your setup ever sets `publishToGuardrails`:

```bash
--set guardrailsService.kafka.enabled=false
```

**Semantic cache for guardrails (bundled Redis + embedder):** both are on by
default and needed together - the cache can't do anything without embeddings,
and vice versa. Sync a real password under `guardrailsRedis.passwordKey`
(default `guardrailsRedisPassword`) into Key Vault - **required, not
optional**, given the default above: the Deployment won't start at all
without it.

Point at an external Redis instead (must have the RediSearch module -
redis-stack-server, not plain redis) by setting `guardrailsRedis.enabled=false`
and syncing a full connection string under `guardrailsService.env.redisUrlKey`
(default `guardrailsRedisUrl`) instead. Turn the whole semantic cache off
entirely by setting both `guardrailsRedis.enabled=false` and
`embedder.enabled=false` - the cache just stays off (fail-open) with neither
configured.

**Model-provider config:** split by whether it's a credential. API
keys/service-account key JSON go through Key Vault same as everything else -
e.g. `openaiApiKey` (see the comment above `agentGuard.env` in `values.yaml`
for the full list of expected Key Vault key names; each is read with
`optional: true`, so an unsynced one just leaves that env var unset).
Everything else - base URLs, deployment/model names, project/location/endpoint
IDs, and `defaultModelConfigJson` - isn't a secret, so it's a plain
`--set`/`-f` value under `agentGuard.env` instead, e.g. `openaiModel`.

**Run only part of the stack** — every component has an `enabled` flag. To turn off
AI guardrails entirely, disable both the http and kafka entrypoints (kafka is on by
default) along with agent-guard/anonymizer, or rendering fails fast with
`scannerApiUrl must be set when agentGuard.enabled=false`:

```bash
--set guardrailsService.http.enabled=false --set guardrailsService.kafka.enabled=false \
--set agentGuard.enabled=false --set anonymizer.enabled=false
```

## Node scheduling

**`nodeSelector` defaults to `{workload: cpu}` on every component** — meant to
keep pods off a GPU nodepool if your cluster has one. This is a real
label match, not a placeholder: if no node in your cluster is labeled
`workload=cpu`, every pod stays `Pending` after a fresh install. Check your
actual node labels first (`kubectl get nodes --show-labels`) and override to
match, or clear it, before installing:

```bash
--set nodeSelector.workload=<your-actual-value>
# or, to disable entirely (note: --set-json nodeSelector='{}' does NOT work -
# Helm merges the empty map into the default, leaving workload: cpu in place):
--set nodeSelector=null
```

## Values reference

`helm show values akto/akto-regional-setup` prints the annotated file.

| Key | Default | Notes |
|---|---|---|
| `nodeSelector` | `{workload: cpu}` | See "Node scheduling" above - verify this label exists on your cluster before installing |
| `central.databaseAbstractorUrl` | `""` → Akto SaaS | Your central install |
| `central.threatBackendUrl` | `""` → Akto SaaS | Your central install |
| `global.keyVault.enabled` | `true` | Mounts the secrets-store CSI volume. Set `false` to skip it and supply `global.keyVault.secretName` as a Secret you create yourself |
| `global.keyVault.secretProviderClass` | `akto-keyvault` | The SecretProviderClass the CSI volume mounts; ignored when `global.keyVault.enabled=false` |
| `central.databaseAbstractorTokenKey` | `databaseAbstractorToken` | Key inside the synced Secret |
| `global.accountName` / `configName` | `Helios` / `staging` | |
| `global.aktoLogLevel` | `INFO` | Applied to every component |
| `miniRuntime.enabled` | `true` | Hosts the traffic Kafka bus |
| `miniRuntime.env.guardrailRedactionEnabled` | `"true"` | Redacts stored payloads via guardrails-service. Needs `guardrailsService.http.enabled` or an explicit `miniRuntime.env.guardrailRedactionUrl` |
| `miniRuntime.env.guardrailRedactionSkipOnUnavailable` | `"true"` | `true` drops payloads that could not be redacted; `false` stores them unredacted, marked `UNAVAILABLE` |
| `threatClient.enabled` | `true` | Own Kafka sidecar by default |
| `dataIngestion.enabled` | `true` | |
| `lambdaEgressProxy.enabled` | `false` | Opt-in. Also set `lambdaEgressProxy.mitmproxy.caKey` or the CA is regenerated on every restart |
| `lambdaEgressProxy.mitmproxy.caKey` | `""` | Secret key holding `mitmproxy-ca.pem` (key + cert). Blank = ephemeral CA |
| `lambdaEgressProxy.service.internal` | `false` | `true` = private load balancer, callers must be inside the VPC. `false` = internet-facing. Scheme cannot be changed in place - see below |
| `lambdaEgressProxy.service.loadBalancerSourceRanges` | `[]` | CIDR strings allowed to connect. Empty = anywhere. Set this whenever `internal` is `false` |
| `guardrailsService.http.enabled` | `true` | |
| `guardrailsService.kafka.enabled` | `true` | Auto-targets mini-runtime's broker unless `guardrailsKafka.enabled` |
| `agentGuard.enabled` | `true` | |
| `anonymizer.enabled` | `true` | |
| `embedder.enabled` | `true` | Semantic cache - needed together with `guardrailsRedis.enabled` |
| `guardrailsRedis.enabled` | `true` | Bundled redis-stack-server for the semantic cache |
| `guardrailsKafka.enabled` | `false` | |
| `networkPolicy.enabled` | `true` | Default-deny egress |

## Migrating from the old charts

The old charts are unchanged and still installable. To move over:

1. Install `akto-regional-setup` into a new namespace with your `central` values.
2. Confirm traffic still flows and threat/guardrails events reach central.
3. Repoint traffic senders at the new `data-ingestion` Service.
4. Uninstall `akto-mini-runtime`, `akto-threat-client`,
   `data-ingestion-service`, `akto-ai-guardrails-v2`.

Value paths changed and `--reuse-values` from an old release will **not** carry
over. Notable differences:

- **The threat client is its own Deployment**, not a container inside
  mini-runtime. It has its own resources, replicas and NetworkPolicy.
- **Redis and fluent-bit are not deployed.** The guardrails semantic cache needs
  a Redis with RediSearch; sync its connection URL into Key Vault under the key
  named by `guardrailsService.env.redisUrlKey` and set `embedder.enabled=true`.
  Leaving that key unsynced keeps the cache off, which is fail-open and safe.
- **One token, one Secret, always Key Vault.** Each component no longer has its
  own token value, and there is no plaintext or bring-your-own-Secret path for
  any credential in this chart - see [Install](#install).
- **Keel is not deployed.** `imageAutoUpdate.enabled=true` only adds the
  keel.sh annotations.
