#!/usr/bin/env bash
# Integration tests for akto-mini-runtime Helm chart.
# Requires: helm, kubectl pointed at a live cluster with sufficient resources.
#
# Usage:
#   ./charts/mini-runtime/tests/integration_test.sh --token <token>            # run all scenarios
#   ./charts/mini-runtime/tests/integration_test.sh --token <token> 1          # run scenario 1 only
#   ./charts/mini-runtime/tests/integration_test.sh --token <token> 1 3 6      # run scenarios 1, 3, and 6
#
# Each scenario installs the chart into its own namespace, runs assertions,
# then cleans up. Cleanup also runs on script exit/interrupt via trap.
# Final exit code is 1 if any assertion failed.

set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# ── Parse arguments ───────────────────────────────────────────────────────────
# Usage: integration_test.sh [--token <token>] [scenario numbers...]
DB_TOKEN=""
SCENARIOS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)
      DB_TOKEN="$2"
      shift 2
      ;;
    *)
      SCENARIOS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$DB_TOKEN" ]]; then
  echo "Error: --token <databaseAbstractorToken> is required"
  echo "Usage: $0 [--token <token>] [scenario numbers...]"
  exit 1
fi

run_scenario() {
  local n="$1"
  if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
    return 0
  fi
  for s in "${SCENARIOS[@]}"; do
    [[ "$s" == "$n" ]] && return 0
  done
  return 1
}

# ── Colour codes ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Helper: print section header ──────────────────────────────────────────────
header() {
  echo ""
  echo -e "${YELLOW}══════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  $1${NC}"
  echo -e "${YELLOW}══════════════════════════════════════════${NC}"
}

# ── Helper: assert two values are equal ───────────────────────────────────────
assert_eq() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo -e "  ${GREEN}✓ PASS${NC}  $label"
    (( PASS++ )) || true
  else
    echo -e "  ${RED}✗ FAIL${NC}  $label"
    echo -e "         expected: ${expected}"
    echo -e "         actual:   ${actual}"
    (( FAIL++ )) || true
  fi
}

# ── Helper: assert a count is zero ────────────────────────────────────────────
assert_zero() {
  local label="$1"
  local count="$2"
  if [[ "$count" -eq 0 ]]; then
    echo -e "  ${GREEN}✓ PASS${NC}  $label"
    (( PASS++ )) || true
  else
    echo -e "  ${RED}✗ FAIL${NC}  $label (count=$count, expected 0)"
    (( FAIL++ )) || true
  fi
}

# ── Helper: assert a string matches a pattern ─────────────────────────────────
assert_match() {
  local label="$1"
  local value="$2"
  local pattern="$3"
  if echo "$value" | grep -q "$pattern"; then
    echo -e "  ${GREEN}✓ PASS${NC}  $label"
    (( PASS++ )) || true
  else
    echo -e "  ${RED}✗ FAIL${NC}  $label"
    echo -e "         value:   ${value}"
    echo -e "         pattern: ${pattern}"
    (( FAIL++ )) || true
  fi
}

# ── Helper: assert a resource exists ─────────────────────────────────────────
assert_exists() {
  local label="$1"
  shift
  if kubectl get "$@" &>/dev/null; then
    echo -e "  ${GREEN}✓ PASS${NC}  $label"
    (( PASS++ )) || true
  else
    echo -e "  ${RED}✗ FAIL${NC}  $label (resource not found)"
    (( FAIL++ )) || true
  fi
}

# ── Helper: kubectl wait with descriptive output ──────────────────────────────
run_wait() {
  local label="$1"
  local timeout="$2"
  shift 2
  local deadline=$(( $(date +%s) + timeout ))
  # kubectl wait exits immediately with "no matching resources found" if the
  # resource doesn't exist yet. Retry in a loop until the deadline.
  while true; do
    if kubectl wait "$@" --timeout=5s 2>/dev/null; then
      echo -e "  ${GREEN}✓ PASS${NC}  $label"
      (( PASS++ )) || true
      return
    fi
    if [[ $(date +%s) -ge $deadline ]]; then
      echo -e "  ${RED}✗ FAIL${NC}  $label (timed out after ${timeout}s)"
      (( FAIL++ )) || true
      return
    fi
    sleep 5
  done
}

# ── Cleanup: track all releases+namespaces to remove ─────────────────────────
CLEANUP_RELEASES=()
CLEANUP_NAMESPACES=()

cleanup() {
  if [[ ${#CLEANUP_RELEASES[@]} -gt 0 ]]; then
    echo ""
    echo "── Cleaning up ──────────────────────────────────────────"
    for i in "${!CLEANUP_RELEASES[@]}"; do
      local release="${CLEANUP_RELEASES[$i]}"
      local ns="${CLEANUP_NAMESPACES[$i]}"
      echo "  Uninstalling $release from $ns..."
      #helm uninstall "$release" -n "$ns" --ignore-not-found 2>/dev/null || true
      # Delete PVCs explicitly — helm uninstall does not remove PVCs created by
      # Strimzi StatefulSets (they are outside Helm's ownership). Leaving them
      # behind causes "Invalid cluster.id" errors on the next install.
      #kubectl delete pvc --all -n "$ns" --ignore-not-found 2>/dev/null || true
      #kubectl delete namespace "$ns" --ignore-not-found 2>/dev/null || true
    done
  fi
}
trap cleanup EXIT

# ── Minimal resource overrides for test environments (e.g. minikube) ─────────
MINIKUBE_RESOURCES=(
  --set kafkaCluster.broker.resources.requests.cpu=200m
  --set kafkaCluster.broker.resources.requests.memory=512Mi
  --set kafkaCluster.broker.resources.limits.cpu=500m
  --set kafkaCluster.broker.resources.limits.memory=1Gi
  --set kafkaCluster.controller.resources.requests.cpu=100m
  --set kafkaCluster.controller.resources.requests.memory=256Mi
  --set kafkaCluster.controller.resources.limits.cpu=200m
  --set kafkaCluster.controller.resources.limits.memory=512Mi
  --set mini_runtime.aktoApiSecurityRuntime.resources.requests.cpu=100m
  --set mini_runtime.aktoApiSecurityRuntime.resources.requests.memory=256Mi
  --set mini_runtime.aktoApiSecurityRuntime.resources.limits.cpu=500m
  --set mini_runtime.aktoApiSecurityRuntime.resources.limits.memory=512Mi
)

# ── Pre-flight ────────────────────────────────────────────────────────────────
header "Pre-flight"
echo "  Chart: $CHART_DIR"
echo "  Cluster: $(kubectl config current-context)"
if [[ ${#SCENARIOS[@]} -gt 0 ]]; then
  echo "  Running scenarios: ${SCENARIOS[*]}"
else
  echo "  Running scenarios: all"
fi
echo ""

echo "  Updating chart dependencies..."
helm repo add strimzi https://strimzi.io/charts/ --force-update >/dev/null 2>&1
helm dependency update "$CHART_DIR" >/dev/null 2>&1
echo -e "  ${GREEN}✓${NC} Dependencies updated"


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 1: Default install — Strimzi Kafka mode
# ══════════════════════════════════════════════════════════════════════════════
if run_scenario 1; then
header "Scenario 1: Default install (Strimzi Kafka mode)"

NS1="default"
REL1="akto-mini-runtime"
CLEANUP_RELEASES+=("$REL1")
CLEANUP_NAMESPACES+=("$NS1")

kubectl create namespace "$NS1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm install "$REL1" "$CHART_DIR" -n "$NS1" \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="$DB_TOKEN" \
  # "${MINIKUBE_RESOURCES[@]}" \
  --wait=false 2>&1 | tail -1

run_wait "[S1] Strimzi operator available" 300 \
  deployment --selector app.kubernetes.io/name=strimzi-kafka-operator \
  -n "$NS1" --for=condition=available

run_wait "[S1] Kafka controller+broker pods ready" 360 \
  pod -l strimzi.io/cluster=akto-kafka \
  -n "$NS1" --for=condition=ready

assert_exists "[S1] akto-kafka-kafka-bootstrap Service exists" \
  service akto-kafka-kafka-bootstrap -n "$NS1"

for topic in akto.api.logs akto.api.logs2 akto.api.producer.logs akto.daemonset.producer.heartbeats; do
  run_wait "[S1] KafkaTopic $topic ready" 120 \
    kafkatopic "$topic" -n "$NS1" --for=condition=ready
done

run_wait "[S1] Redis available" 120 \
  deployment/${REL1}-akto-mini-runtime-redis \
  -n "$NS1" --for=condition=available

run_wait "[S1] Keel available (validates /healthz liveness)" 180 \
  deployment/${REL1}-akto-mini-runtime-keel \
  -n "$NS1" --for=condition=available

run_wait "[S1] mini-runtime init container passed (Kafka TCP verified)" 240 \
  pod -l app=${REL1}-akto-mini-runtime-mini-runtime \
  -n "$NS1" --for=condition=initialized

PHASE=$(kubectl get pod -l app=${REL1}-akto-mini-runtime-mini-runtime \
  -n "$NS1" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
if [[ "$PHASE" == "Pending" ]]; then
  echo -e "  ${RED}✗ FAIL${NC}  [S1] mini-runtime pod stuck in Pending"
  kubectl describe pod -l app=${REL1}-akto-mini-runtime-mini-runtime -n "$NS1" | tail -20
  (( FAIL++ )) || true
else
  echo -e "  ${GREEN}✓ PASS${NC}  [S1] mini-runtime pod phase=$PHASE (Running or CrashLoopBackOff OK)"
  (( PASS++ )) || true
fi

run_wait "[S1] threat-client init container passed" 240 \
  pod -l app=${REL1}-akto-mini-runtime-threat-client \
  -n "$NS1" --for=condition=initialized

fi # end scenario 1


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 2: External Kafka mode
# ══════════════════════════════════════════════════════════════════════════════
if run_scenario 2; then
header "Scenario 2: External Kafka mode"

NS2="akto-int-ext"
REL2="akto-ext"
CLEANUP_RELEASES+=("$REL2")
CLEANUP_NAMESPACES+=("$NS2")

kubectl create namespace "$NS2" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

EXTERNAL_BROKER="kafka-stub.${NS2}.svc.cluster.local:9092"

helm install "$REL2" "$CHART_DIR" -n "$NS2" \
  --set kafkaCluster.enabled=false \
  --set mini_runtime.useExternalKafka=true \
  --set mini_runtime.externalKafka.brokerUrl="$EXTERNAL_BROKER" \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="$DB_TOKEN" \
  --set keel.keel.enabled=false \
  --wait=false 2>&1 | tail -1

KAFKA_COUNT=$(kubectl get kafka -n "$NS2" 2>/dev/null | grep -c "akto-kafka" || true)
assert_zero "[S2] No Kafka CRD resources in namespace" "$KAFKA_COUNT"

SVC_COUNT=$(kubectl get service -n "$NS2" 2>/dev/null | grep -c "akto-kafka" || true)
assert_zero "[S2] No akto-kafka-* Services" "$SVC_COUNT"

BROKER_URL=$(kubectl get deployment ${REL2}-akto-mini-runtime-mini-runtime \
  -n "$NS2" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AKTO_KAFKA_BROKER_URL")].value}' \
  2>/dev/null || echo "")
assert_eq "[S2] AKTO_KAFKA_BROKER_URL == external broker" "$BROKER_URL" "$EXTERNAL_BROKER"

INIT_CONTAINERS=$(kubectl get deployment ${REL2}-akto-mini-runtime-mini-runtime \
  -n "$NS2" \
  -o jsonpath='{.spec.template.spec.initContainers}' \
  2>/dev/null || echo "")
assert_eq "[S2] No wait-for-kafka init container" "$INIT_CONTAINERS" ""

fi # end scenario 2


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 3: TLS enabled
# ══════════════════════════════════════════════════════════════════════════════
if run_scenario 3; then
header "Scenario 3: TLS enabled"

NS3="default"
REL3="akto-tls"
CLEANUP_RELEASES+=("$REL3")
CLEANUP_NAMESPACES+=("$NS3")

kubectl create namespace "$NS3" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm install "$REL3" "$CHART_DIR" -n "$NS3" \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="$DB_TOKEN" \
  --set kafkaCluster.tls=true \
  --set keel.keel.enabled=false \
  "${MINIKUBE_RESOURCES[@]}" \
  --wait=false 2>&1 | tail -1

run_wait "[S3] Strimzi operator available" 300 \
  deployment --selector app.kubernetes.io/name=strimzi-kafka-operator \
  -n "$NS3" --for=condition=available

run_wait "[S3] Kafka pods ready" 360 \
  pod -l strimzi.io/cluster=akto-kafka \
  -n "$NS3" --for=condition=ready

assert_exists "[S3] Strimzi CA cert Secret exists" \
  secret akto-kafka-cluster-ca-cert -n "$NS3"

TLS_LISTENER_NAME=$(kubectl get kafka akto-kafka -n "$NS3" \
  -o jsonpath='{.spec.kafka.listeners[1].name}' 2>/dev/null || echo "")
assert_eq "[S3] Kafka CR has TLS listener named 'tls'" "$TLS_LISTENER_NAME" "tls"

TLS_LISTENER_TLS=$(kubectl get kafka akto-kafka -n "$NS3" \
  -o jsonpath='{.spec.kafka.listeners[1].tls}' 2>/dev/null || echo "")
assert_eq "[S3] Kafka TLS listener has tls=true" "$TLS_LISTENER_TLS" "true"

TLS_ENABLED=$(kubectl get deployment ${REL3}-akto-mini-runtime-mini-runtime \
  -n "$NS3" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AKTO_KAFKA_TLS_ENABLED")].value}' \
  2>/dev/null || echo "")
assert_eq "[S3] mini-runtime has AKTO_KAFKA_TLS_ENABLED=true" "$TLS_ENABLED" "true"

TRUSTSTORE=$(kubectl get deployment ${REL3}-akto-mini-runtime-mini-runtime \
  -n "$NS3" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KAFKA_SSL_TRUSTSTORE_LOCATION")].value}' \
  2>/dev/null || echo "")
assert_eq "[S3] mini-runtime has KAFKA_SSL_TRUSTSTORE_LOCATION=/etc/kafka/tls/ca.crt" \
  "$TRUSTSTORE" "/etc/kafka/tls/ca.crt"

TLS_VOLUME_SECRET=$(kubectl get deployment ${REL3}-akto-mini-runtime-mini-runtime \
  -n "$NS3" \
  -o jsonpath='{.spec.template.spec.volumes[?(@.name=="kafka-tls-ca")].secret.secretName}' \
  2>/dev/null || echo "")
assert_eq "[S3] mini-runtime kafka-tls-ca volume references akto-kafka-cluster-ca-cert" \
  "$TLS_VOLUME_SECRET" "akto-kafka-cluster-ca-cert"

fi # end scenario 3


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 4: Port override (plain port 9094)
# ══════════════════════════════════════════════════════════════════════════════
if run_scenario 4; then
header "Scenario 4: Port override (kafkaCluster.ports.plain=9094)"

NS4="akto-int-port"
REL4="akto-port"
CLEANUP_RELEASES+=("$REL4")
CLEANUP_NAMESPACES+=("$NS4")

kubectl create namespace "$NS4" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm install "$REL4" "$CHART_DIR" -n "$NS4" \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="$DB_TOKEN" \
  --set kafkaCluster.ports.plain=9094 \
  --set keel.keel.enabled=false \
  "${MINIKUBE_RESOURCES[@]}" \
  --wait=false 2>&1 | tail -1

run_wait "[S4] Strimzi operator available" 300 \
  deployment --selector app.kubernetes.io/name=strimzi-kafka-operator \
  -n "$NS4" --for=condition=available

LISTENER_PORT=$(kubectl get kafka akto-kafka -n "$NS4" \
  -o jsonpath='{.spec.kafka.listeners[0].port}' 2>/dev/null || echo "")
assert_eq "[S4] Kafka CR plain listener port == 9094" "$LISTENER_PORT" "9094"

assert_exists "[S4] akto-kafka-kafka-bootstrap Service exists" \
  service akto-kafka-kafka-bootstrap -n "$NS4"

BROKER_URL=$(kubectl get deployment ${REL4}-akto-mini-runtime-mini-runtime \
  -n "$NS4" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AKTO_KAFKA_BROKER_URL")].value}' \
  2>/dev/null || echo "")
assert_match "[S4] AKTO_KAFKA_BROKER_URL contains :9094" "$BROKER_URL" ":9094"

BROKER_MAL=$(kubectl get deployment ${REL4}-akto-mini-runtime-mini-runtime \
  -n "$NS4" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AKTO_KAFKA_BROKER_MAL")].value}' \
  2>/dev/null || echo "")
assert_match "[S4] AKTO_KAFKA_BROKER_MAL contains :9094" "$BROKER_MAL" ":9094"

INIT_CMD=$(kubectl get deployment ${REL4}-akto-mini-runtime-mini-runtime \
  -n "$NS4" \
  -o jsonpath='{.spec.template.spec.initContainers[0].command[2]}' \
  2>/dev/null || echo "")
assert_match "[S4] wait-for-kafka init container uses KAFKA_PORT=9094" "$INIT_CMD" 'KAFKA_PORT="9094"'

fi # end scenario 4


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 5: Service annotations + pod/deployment annotations
# ══════════════════════════════════════════════════════════════════════════════
if run_scenario 5; then
header "Scenario 5: Service annotations and pod/deployment annotations"

NS5="akto-int-ann"
REL5="akto-ann"
CLEANUP_RELEASES+=("$REL5")
CLEANUP_NAMESPACES+=("$NS5")

kubectl create namespace "$NS5" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm install "$REL5" "$CHART_DIR" -n "$NS5" \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="$DB_TOKEN" \
  --set "kafkaCluster.serviceAnnotations.test\.akto\.io/ci-marker=integration-test" \
  --set "mini_runtime.podAnnotations.prometheus\.io/scrape=true" \
  --set "mini_runtime.deploymentAnnotations.team=platform" \
  --set keel.keel.enabled=false \
  "${MINIKUBE_RESOURCES[@]}" \
  --wait=false 2>&1 | tail -1

BOOTSTRAP_ANN=$(kubectl get kafka akto-kafka -n "$NS5" \
  -o jsonpath='{.spec.kafka.template.bootstrapService.metadata.annotations.test\.akto\.io/ci-marker}' \
  2>/dev/null || echo "")
assert_eq "[S5] Kafka CR bootstrapService annotation set" \
  "$BOOTSTRAP_ANN" "integration-test"

BROKERS_ANN=$(kubectl get kafka akto-kafka -n "$NS5" \
  -o jsonpath='{.spec.kafka.template.brokersService.metadata.annotations.test\.akto\.io/ci-marker}' \
  2>/dev/null || echo "")
assert_eq "[S5] Kafka CR brokersService annotation set" \
  "$BROKERS_ANN" "integration-test"

DEPLOY_ANN=$(kubectl get deployment ${REL5}-akto-mini-runtime-mini-runtime \
  -n "$NS5" \
  -o jsonpath='{.metadata.annotations.team}' \
  2>/dev/null || echo "")
assert_eq "[S5] mini-runtime Deployment has annotation team=platform" "$DEPLOY_ANN" "platform"

POD_ANN=$(kubectl get deployment ${REL5}-akto-mini-runtime-mini-runtime \
  -n "$NS5" \
  -o jsonpath='{.spec.template.metadata.annotations.prometheus\.io/scrape}' \
  2>/dev/null || echo "")
assert_eq "[S5] mini-runtime pod template has prometheus.io/scrape=true" "$POD_ANN" "true"

run_wait "[S5] Strimzi operator available (for Service annotation reconciliation)" 300 \
  deployment --selector app.kubernetes.io/name=strimzi-kafka-operator \
  -n "$NS5" --for=condition=available

echo "  Waiting 30s for Strimzi to reconcile Services..."
sleep 30

LIVE_SVC_ANN=$(kubectl get service akto-kafka-kafka-bootstrap -n "$NS5" \
  -o jsonpath='{.metadata.annotations.test\.akto\.io/ci-marker}' \
  2>/dev/null || echo "")
assert_eq "[S5] Live akto-kafka-kafka-bootstrap Service has annotation" \
  "$LIVE_SVC_ANN" "integration-test"

fi # end scenario 5


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 6: SASL / SCRAM-SHA-512
# ══════════════════════════════════════════════════════════════════════════════
if run_scenario 6; then
header "Scenario 6: SASL (SCRAM-SHA-512)"

NS6="default"
REL6="akto-mini-runtime"
CLEANUP_RELEASES+=("$REL6")
CLEANUP_NAMESPACES+=("$NS6")

kubectl create namespace "$NS6" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm install "$REL6" "$CHART_DIR" -n "$NS6" \
  --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="$DB_TOKEN" \
  --set kafkaCluster.sasl.enabled=true \
  --set kafkaCluster.sasl.username=akto-runtime \
  --set kafkaCluster.sasl.password=ci-sasl-secret \
  # "${MINIKUBE_RESOURCES[@]}" \
  --wait=false 2>&1 | tail -1

run_wait "[S6] Strimzi operator available" 300 \
  deployment --selector app.kubernetes.io/name=strimzi-kafka-operator \
  -n "$NS6" --for=condition=available

run_wait "[S6] KafkaUser akto-runtime ready (user operator provisioned credentials)" 180 \
  kafkauser/akto-runtime -n "$NS6" --for=condition=ready

assert_exists "[S6] akto-kafka-sasl-credentials Secret exists" \
  secret akto-kafka-sasl-credentials -n "$NS6"

SASL_USERNAME=$(kubectl get secret akto-kafka-sasl-credentials -n "$NS6" \
  -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
assert_eq "[S6] SASL Secret username == akto-runtime" "$SASL_USERNAME" "akto-runtime"

AUTH_ENABLED=$(kubectl get deployment ${REL6}-akto-mini-runtime-mini-runtime \
  -n "$NS6" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KAFKA_AUTH_ENABLED")].value}' \
  2>/dev/null || echo "")
assert_eq "[S6] mini-runtime has KAFKA_AUTH_ENABLED=true" "$AUTH_ENABLED" "true"

SECRET_REF=$(kubectl get deployment ${REL6}-akto-mini-runtime-mini-runtime \
  -n "$NS6" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KAFKA_USERNAME")].valueFrom.secretKeyRef.name}' \
  2>/dev/null || echo "")
assert_eq "[S6] mini-runtime KAFKA_USERNAME reads from akto-kafka-sasl-credentials" \
  "$SECRET_REF" "akto-kafka-sasl-credentials"

LISTENER_AUTH=$(kubectl get kafka akto-kafka -n "$NS6" \
  -o jsonpath='{.spec.kafka.listeners[0].authentication.type}' \
  2>/dev/null || echo "")
assert_eq "[S6] Kafka listener authentication.type == scram-sha-512" \
  "$LISTENER_AUTH" "scram-sha-512"

fi # end scenario 6


# ══════════════════════════════════════════════════════════════════════════════
# Results
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}══════════════════════════════════════════${NC}"
if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}  Results: $PASS passed, $FAIL failed${NC}"
else
  echo -e "${RED}  Results: $PASS passed, $FAIL failed${NC}"
fi
echo -e "${YELLOW}══════════════════════════════════════════${NC}"

[[ $FAIL -eq 0 ]]
