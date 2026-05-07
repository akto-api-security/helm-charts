#!/usr/bin/env bash
# Run all automated tests for the mini-runtime chart.
# Requires: helm, helm-unittest plugin (helm plugin install https://github.com/helm-unittest/helm-unittest)
#
# Usage:
#   ./charts/mini-runtime/tests/run_tests.sh

set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== helm lint ==="
helm lint "$CHART_DIR"

echo ""
echo "=== helm lint: SASL enabled ==="
helm lint "$CHART_DIR" \
  --set kafkaCluster.sasl.enabled=true \
  --set kafkaCluster.sasl.password=secret

echo ""
echo "=== helm lint: TLS enabled ==="
helm lint "$CHART_DIR" \
  --set kafkaCluster.tls=true

echo ""
echo "=== helm lint: SASL + TLS ==="
helm lint "$CHART_DIR" \
  --set kafkaCluster.sasl.enabled=true \
  --set kafkaCluster.sasl.password=secret \
  --set kafkaCluster.tls=true

echo ""
echo "=== helm lint: external Kafka ==="
helm lint "$CHART_DIR" \
  --set kafkaCluster.enabled=false \
  --set mini_runtime.useExternalKafka=true \
  --set mini_runtime.externalKafka.brokerUrl=kafka1:9092

echo ""
echo "=== helm lint: external Kafka with SASL_SSL ==="
helm lint "$CHART_DIR" \
  --set kafkaCluster.enabled=false \
  --set mini_runtime.useExternalKafka=true \
  --set mini_runtime.externalKafka.brokerUrl=kafka1:9092 \
  --set mini_runtime.externalKafka.username=user \
  --set mini_runtime.externalKafka.password=pass \
  --set mini_runtime.externalKafka.saslMechanism=SCRAM-SHA-256 \
  --set mini_runtime.externalKafka.useSsl=true \
  --set mini_runtime.externalKafka.securityProtocol=SASL_SSL

echo ""
echo "=== helm lint: port override ==="
helm lint "$CHART_DIR" \
  --set kafkaCluster.ports.plain=9094

echo ""
echo "=== helm unittest ==="
helm unittest "$CHART_DIR"

echo ""
echo "All tests passed."
