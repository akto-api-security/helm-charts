# Publishing Mini-Runtime Helm Charts

## Chart Structure

The mini-runtime charts use a simple 2-chart structure:

- **mini-runtime**: Base chart with templates and values
  - Runtime & Threat-client: Use `latest` tags
  - Kafka, Keel, Redis: Use versioned tags (stable infrastructure)

- **mini-runtime-versioned**: Wrapper chart that depends on mini-runtime
  - Overrides only Runtime & Threat-client to use specific versions
  - Inherits all other values from mini-runtime

## Publishing to Helm Registry

### Prerequisites

Both charts must be published to your Helm repository for the dependency resolution to work when users install from the registry.

### Publishing Steps

When you're ready to release:

1. **Update chart versions** (if needed):
   - `charts/mini-runtime/Chart.yaml` - version field
   - `charts/mini-runtime-versioned/Chart.yaml` - version field and dependency version

2. **Update image tags** (if needed):
   - **For infrastructure updates (Kafka/Keel/Redis)**: Update `charts/mini-runtime/values.yaml`
   - **For application version updates**: Update `charts/mini-runtime-versioned/values.yaml`

3. **Commit and push** to trigger GitHub Actions:
   ```bash
   git add charts/mini-runtime*
   git commit -m "Release mini-runtime charts v0.5.9"
   git push origin master
   ```

4. Your existing GitHub Actions workflow will automatically:
   - Package both charts
   - Publish to GitHub Pages
   - Update the Helm repository index

### How It Works

**Local Development:**
- mini-runtime-versioned uses `repository: file://../mini-runtime` in Chart.yaml
- Run `helm dependency update` to link to local mini-runtime chart
- Works perfectly for testing

**Published to Registry:**
- Users run: `helm repo add akto https://akto-api-security.github.io/helm-charts`
- When installing mini-runtime-versioned, Helm automatically:
  - Finds the mini-runtime dependency in the same repo
  - Downloads and uses it

### User Installation

Users can now choose between two charts:

```bash
# Add the repo once
helm repo add akto https://akto-api-security.github.io/helm-charts
helm repo update

# Install with latest application tags (runtime & threat-client)
helm install my-runtime akto/akto-mini-runtime

# OR install with all versioned tags
helm install my-runtime akto/akto-mini-runtime-versioned
```

## Maintenance

### For Feature/Template Changes
1. Update `charts/mini-runtime/templates/` or `charts/mini-runtime/values.yaml`
2. Bump version in both Chart.yaml files
3. Commit and push

### For Infrastructure Version Updates (Kafka/Keel/Redis)
1. Update `charts/mini-runtime/values.yaml` with new infrastructure versions
2. Bump version in both Chart.yaml files
3. Commit and push
4. Both charts will use the new infrastructure versions

### For Application Version Updates (Runtime/Threat-client)
1. Update `charts/mini-runtime-versioned/values.yaml` with new application versions
2. Bump version in mini-runtime-versioned/Chart.yaml
3. Commit and push
4. mini-runtime continues using `latest`, mini-runtime-versioned uses new versions

### Version Sync
Keep these versions in sync:
- `mini-runtime/Chart.yaml` version X.Y.Z
- `mini-runtime-versioned/Chart.yaml` version X.Y.Z and dependency version X.Y.Z

## Testing Before Publishing

Always test locally before pushing:

```bash
# Test mini-runtime (latest runtime & threat-client, versioned infrastructure)
cd charts/mini-runtime
helm template test . | grep "image:"

# Expected:
# - akto-api-security-mini-runtime:latest
# - confluentinc-cp-kafka:8.1.1-1-ubi9
# - keelhq-keel:akto_v1.0.0
# - akto-threat-detection:latest
# - redis:7.0

# Test mini-runtime-versioned (all versioned)
cd charts/mini-runtime-versioned
helm dependency update
helm template test . | grep "image:"

# Expected:
# - akto-api-security-mini-runtime:1.57.6_local
# - confluentinc-cp-kafka:8.1.1-1-ubi9
# - keelhq-keel:akto_v1.0.0
# - akto-threat-detection:1.6.7
# - redis:7.0
```
