#!/bin/bash
# Validates that every image in values.yaml uses a correctly formatted digest.
# Run this before releasing the sha chart.

set -euo pipefail

VALUES="charts/mini-runtime-sha/values.yaml"
ERRORS=0

echo "Validating image digests in $VALUES..."

# Fail if any `tag:` field exists under an image block
while IFS= read -r line; do
  if echo "$line" | grep -qE '^\s+tag\s*:'; then
    echo "ERROR: Found 'tag' field (must use digest instead): $line"
    ERRORS=$((ERRORS + 1))
  fi
done < "$VALUES"

# Validate every digest: value matches sha256:<64 lowercase hex chars>
while IFS= read -r line; do
  if echo "$line" | grep -qE '^\s+digest\s*:'; then
    value=$(echo "$line" | sed 's/.*digest\s*:\s*//' | tr -d '"' | tr -d "'" | xargs)
    if [ -z "$value" ]; then
      echo "ERROR: Empty digest: $line"
      ERRORS=$((ERRORS + 1))
    elif ! echo "$value" | grep -qE '^sha256:[a-f0-9]{64}$'; then
      echo "ERROR: Invalid digest format (expected sha256:<64 hex chars>): $line"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done < "$VALUES"

# Verify every image repository has a corresponding digest entry
REPO_COUNT=$(grep -cE '^\s+repository\s*:' "$VALUES" || true)
DIGEST_COUNT=$(grep -cE '^\s+digest\s*:' "$VALUES" || true)

if [ "$REPO_COUNT" -ne "$DIGEST_COUNT" ]; then
  echo "ERROR: Mismatch — found $REPO_COUNT image repositories but only $DIGEST_COUNT digest entries. Every image must have a digest."
  ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "FAILED: $ERRORS error(s). All images in the sha chart must use valid digests (sha256:<64 hex chars>)."
  exit 1
fi

echo "OK: All $DIGEST_COUNT images have valid sha256 digests."
