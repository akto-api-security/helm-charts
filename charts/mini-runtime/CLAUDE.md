# akto-mini-runtime Helm Chart

## Overview

Deploys the Akto hybrid runtime stack into a Kubernetes cluster. The chart installs:
- **mini-runtime** deployment — API security runtime container
- **Strimzi Kafka cluster** (default) — Strimzi operator + KafkaNodePool, Kafka, KafkaTopic CRDs via Helm subchart dependency
- **Keel** deployment (auto-updater)
- **Threat detection client** deployment
- **Redis** deployment (when threat client + aggregation rules enabled)

**Two Kafka modes:**
- **Strimzi mode** (default, `kafkaCluster.enabled: true`) — Strimzi operator and Kafka cluster deployed automatically by this chart
- **External mode** (`mini_runtime.useExternalKafka: true`) — bring your own Kafka; disables all Strimzi resources

**Current install command:**
```sh
helm install akto-mini-runtime akto/akto-mini-runtime -n dev \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken=""
```

**External Kafka install command:**
```sh
helm install akto-mini-runtime akto/akto-mini-runtime -n dev \
  --set kafkaCluster.enabled=false \
  --set mini_runtime.useExternalKafka=true \
  --set mini_runtime.externalKafka.brokerUrl="kafka1:9092" \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken=""
```

---

## Required Values

| Value | Description |
|-------|-------------|
| `mongo.aktoMongoConn` | MongoDB connection string. Injected as `AKTO_MONGO_CONN` into the runtime container. |
| `mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken` | Auth token for database abstractor service (cyborg.akto.io). Injected as `DATABASE_ABSTRACTOR_SERVICE_TOKEN` into runtime and as `AKTO_THREAT_PROTECTION_BACKEND_TOKEN` / `DATABASE_ABSTRACTOR_SERVICE_TOKEN` into the threat client. Can alternatively be provided via Kubernetes secret (see Secret Management). |

---

## Strimzi Kafka Cluster (`kafkaCluster`)

### Quick start

```sh
helm install akto-mini-runtime akto/akto-mini-runtime -n dev \
  --set kafkaCluster.enabled=true \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="<token>"
```

This will:
1. Install the Strimzi operator via the bundled Helm subchart dependency
2. Deploy a 1-broker + 1-controller KRaft Kafka cluster named `my-cluster`
3. Create 4 KafkaTopics (`akto.api.logs`, `akto.api.logs2`, `akto.api.producer.logs`, `akto.daemonset.producer.heartbeats`)
4. Auto-configure the runtime and threat client to connect to `my-cluster-kafka-bootstrap.<namespace>.svc.cluster.local:9092`

### Strimzi operator

The Strimzi operator is bundled as a Helm subchart (`strimzi/strimzi-kafka-operator 0.51.0`). It is installed automatically when `kafkaCluster.enabled: true` and skipped when `kafkaCluster.enabled: false` (external Kafka mode). Helm handles idempotency — re-installing or upgrading is safe even if the operator is already present.

### Cluster topology

```yaml
kafkaCluster:
  clusterName: "my-cluster"
  broker:
    replicas: 3
    storage:
      size: "10Gi"
      storageClass: ""     # empty = default StorageClass
      deleteClaim: true
  controller:
    replicas: 1
    storage:
      size: "10Gi"
      storageClass: ""
      deleteClaim: true
```

### Retention / replication

```yaml
kafkaCluster:
  config:
    retentionMs: "604800000"       # 7 days
    retentionBytes: "5368709120"   # 5GB per partition
    cleanupPolicy: "delete"
    defaultReplicationFactor: 3
    minInsyncReplicas: 2
    offsetsTopicReplicationFactor: 3
    transactionStateLogReplicationFactor: 3
    transactionStateLogMinIsr: 2
```

### Port override

```yaml
kafkaCluster:
  ports:
    plain: 9092   # plain (or SASL) listener port — also drives bootstrap URL in runtime/threat-client
    tls: 9093     # TLS listener port (only used when tls: true)
```

Changing `ports.plain` changes both the Strimzi listener port and the bootstrap URL injected into all containers.

### Topics

```yaml
kafkaCluster:
  topics:
    - name: "akto.api.logs"
      partitions: 3
      replicas: 3
    # add more as needed
```

Each entry renders a `KafkaTopic` CRD managed by the Strimzi topic operator.

### Service annotations

Annotations are forwarded to Strimzi-generated Kafka Services via `spec.kafka.template`:

```yaml
kafkaCluster:
  serviceAnnotations:
    service.beta.kubernetes.io/aws-load-balancer-internal: "true"
```

This sets annotations on both `<clusterName>-kafka-bootstrap` and `<clusterName>-kafka-brokers` Services.

---

## Kafka Authentication (Strimzi)

### No auth (default)

```yaml
kafkaCluster:
  sasl:
    enabled: false
  tls: false
```

### SASL only (SCRAM)

```yaml
kafkaCluster:
  sasl:
    enabled: true
    mechanism: "SCRAM-SHA-512"   # SCRAM-SHA-256 or SCRAM-SHA-512
    username: "akto-runtime"
    password: "secret"
    # OR reference an existing Secret (must have keys: username, password):
    useExistingSecret: true
    existingSecret: "my-sasl-secret"
```

Strimzi creates a `KafkaUser` CRD and its user operator provisions the SCRAM credentials automatically — no JAAS config or broker-side init containers needed. The chart creates a `Secret` named `<clusterName>-sasl-credentials` (unless `useExistingSecret: true`).

SASL env vars (`KAFKA_AUTH_ENABLED`, `AKTO_KAFKA_SASL_ENABLED`, `AKTO_KAFKA_SASL_MECHANISM`, `KAFKA_USERNAME`, `KAFKA_PASSWORD`) are injected into both the runtime and threat client containers.

The threat client also receives `AKTO_KAFKA_USERNAME` / `AKTO_KAFKA_PASSWORD` from the same secret.

### TLS only

```yaml
kafkaCluster:
  tls: true
  sasl:
    enabled: false
```

Strimzi auto-generates broker TLS certificates via its internal cluster CA. The CA cert is stored in a Secret named `<clusterName>-cluster-ca-cert` (created by Strimzi, not this chart). The chart mounts this Secret into the runtime and threat client containers at `/etc/kafka/tls/ca.crt` and sets:
- `AKTO_KAFKA_TLS_ENABLED: "true"`
- `AKTO_KAFKA_SECURITY_PROTOCOL: "SSL"`
- `KAFKA_SSL_TRUSTSTORE_LOCATION: "/etc/kafka/tls/ca.crt"`

### SASL + TLS

```yaml
kafkaCluster:
  tls: true
  sasl:
    enabled: true
    mechanism: "SCRAM-SHA-512"
    username: "akto-runtime"
    password: "secret"
```

Sets `AKTO_KAFKA_SECURITY_PROTOCOL: "SASL_SSL"` in containers.

---

## External Kafka (`mini_runtime.useExternalKafka`)

When `kafkaCluster.enabled: false` and `useExternalKafka: true`, point at an existing Kafka cluster:

```yaml
mini_runtime:
  useExternalKafka: true
  externalKafka:
    brokerUrl: "kafka1:9092,kafka2:9092"
    username: ""
    password: ""
    saslMechanism: "SCRAM-SHA-256"   # PLAIN | SCRAM-SHA-256 | SCRAM-SHA-512
    useSsl: false
    securityProtocol: "SASL_SSL"     # PLAINTEXT | SASL_PLAINTEXT | SASL_SSL | SSL
```

No Strimzi CRDs or Kafka Service are created. SASL auth env vars are injected when `username` is non-empty.

---

## Secret Management

### Database Abstractor Token

Option 1 — inline (default):
```yaml
mini_runtime:
  aktoApiSecurityRuntime:
    env:
      databaseAbstractorToken: "<token>"
```

Option 2 — create a new Kubernetes Secret:
```yaml
mini_runtime:
  aktoApiSecurityRuntime:
    env:
      useSecretsForDatabaseAbstractorToken: true
      databaseAbstractorTokenSecrets:
        token: "<token>"
```

Option 3 — reference an existing Secret:
```yaml
mini_runtime:
  aktoApiSecurityRuntime:
    env:
      useSecretsForDatabaseAbstractorToken: true
      databaseAbstractorTokenSecrets:
        existingSecret: "my-existing-secret"
```

### Kafka SASL Credentials (Strimzi)

Use `kafkaCluster.sasl.password` (inline) or `kafkaCluster.sasl.useExistingSecret: true` + `kafkaCluster.sasl.existingSecret` (pre-existing Secret with keys `username` and `password`).

---

## Annotations

Annotation injection points — **not in default values.yaml**, add as needed:

| Value | Applied to |
|-------|-----------|
| `mini_runtime.deploymentAnnotations` | mini-runtime Deployment metadata |
| `mini_runtime.podAnnotations` | mini-runtime Pod template metadata |
| `kafkaCluster.serviceAnnotations` | Strimzi-generated Kafka Services (bootstrap + brokers) |
| `keel.deploymentAnnotations` | Keel Deployment metadata |
| `keel.podAnnotations` | Keel Pod template metadata |
| `threat_client.deploymentAnnotations` | Threat client Deployment metadata |
| `threat_client.podAnnotations` | Threat client Pod template metadata |

---

## Conditional Components

| Component | Enabled when | Default |
|-----------|-------------|---------|
| Strimzi operator (subchart) + Strimzi CRDs (Kafka, NodePools, Topics, User) | `kafkaCluster.enabled: true` | **enabled** |
| Kafka SASL Secret + KafkaUser | `kafkaCluster.enabled: true` AND `kafkaCluster.sasl.enabled: true` AND `useExistingSecret: false` | disabled |
| Strimzi CA cert volume mount | `kafkaCluster.enabled: true` AND `kafkaCluster.tls: true` | disabled |
| Keel deployment + RBAC | `keel.keel.enabled: true` | **enabled** |
| Threat client deployment | `threat_client.aktoApiSecurityThreatClient.env.enabled: true` | **enabled** |
| Redis deployment + Service | Threat client enabled AND `aggregationRulesEnabled: true` | disabled |
| Fluent Bit sidecar | `fluent_bit.enabled: true` | disabled |
| Database abstractor Secret | `useSecretsForDatabaseAbstractorToken: true` AND no existing secret | disabled |

---

## Component Reference

### Runtime Container (`mini_runtime.aktoApiSecurityRuntime`)
- Image: `public.ecr.aws/aktosecurity/akto-api-security-mini-runtime`
- Default resources: 1-2 CPU, 2-4Gi RAM
- HPA: 1–2 replicas at 80% CPU

### Strimzi Kafka
- Kafka version: 4.1.1 (KRaft mode, no Zookeeper)
- 1 controller node + 3 broker nodes (separate pods, managed by Strimzi)
- Bootstrap Service: `<clusterName>-kafka-bootstrap.<namespace>.svc.cluster.local`
- Topic operator and user operator enabled

### Keel (`keel.keel`)
- Image: `public.ecr.aws/aktosecurity/keelhq-keel`
- Polls for image updates every 60 minutes
- Exposed via LoadBalancer on port 9300
- Disable with `keel.keel.enabled: false`

### Threat Client (`threat_client.aktoApiSecurityThreatClient`)
- Image: `public.ecr.aws/aktosecurity/akto-threat-detection`
- Requires Postgres connection (`postgresUrl`, `postgresUser`, `postgresPassword`)
- Disable with `threat_client.aktoApiSecurityThreatClient.env.enabled: false`

### Redis (`redis`)
- Image: `public.ecr.aws/aktosecurity/redis:latestV8.6.2`
- Only deployed when threat client + aggregation rules are enabled
- Optional persistence: `redis.persistence.enabled: true`

### Fluent Bit (`fluent_bit`)
- Optional logging sidecar, disabled by default
- Ships logs to `observability.akto.io` authenticated with the database abstractor token

---

## Pod Scheduling

```yaml
nodeSelector: {}    # e.g. kubernetes.io/arch: amd64
tolerations: []
affinity: {}
```
Applied to all deployments and the Strimzi install Job.

---

## Common Overrides

**Deploy with Strimzi Kafka (first install, Strimzi not yet installed):**
```sh
helm install akto-mini-runtime akto/akto-mini-runtime -n dev \
  --set kafkaCluster.enabled=true \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="<token>"
```

**Strimzi Kafka with SASL (SCRAM-SHA-512):**
```sh
--set kafkaCluster.enabled=true \
--set kafkaCluster.sasl.enabled=true \
--set kafkaCluster.sasl.mechanism="SCRAM-SHA-512" \
--set kafkaCluster.sasl.username="akto-runtime" \
--set kafkaCluster.sasl.password="secret"
```

**Strimzi Kafka with TLS:**
```sh
--set kafkaCluster.enabled=true \
--set kafkaCluster.tls=true
```

**Use external Kafka with SASL_SSL:**
```sh
--set mini_runtime.useExternalKafka=true \
--set mini_runtime.externalKafka.brokerUrl="b1:9092,b2:9092" \
--set mini_runtime.externalKafka.username="user" \
--set mini_runtime.externalKafka.password="pass" \
--set mini_runtime.externalKafka.saslMechanism="SCRAM-SHA-256" \
--set mini_runtime.externalKafka.useSsl=true \
--set mini_runtime.externalKafka.securityProtocol="SASL_SSL"
```

**Disable Keel:**
```sh
--set keel.keel.enabled=false
```

**Disable threat client (skip Redis/Postgres dependency):**
```sh
--set threat_client.aktoApiSecurityThreatClient.env.enabled=false
```

**Override Kafka Service port:**
```sh
--set kafkaCluster.ports.plain=9094
```
