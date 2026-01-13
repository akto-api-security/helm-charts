# Publishing Mini-Runtime Helm Charts

## Chart Structure

The mini-runtime charts use a base + wrapper pattern to avoid duplication:

- **mini-runtime-base**: Contains all templates and default values (base chart)
- **mini-runtime**: Wrapper that uses `latest` image tags
- **mini-runtime-versioned**: Wrapper that uses specific versioned image tags

## Publishing to Helm Registry

### Prerequisites

All three charts must be published to your Helm repository for the dependency resolution to work when users install from the registry.

### Publishing Steps

When you're ready to release:

1. **Update all chart versions** (if needed):
   - `charts/mini-runtime-base/Chart.yaml` - version field
   - `charts/mini-runtime/Chart.yaml` - version field and dependency version
   - `charts/mini-runtime-versioned/Chart.yaml` - version field and dependency version

2. **Update image tags** (if needed):
   - For versioned releases: Update `charts/mini-runtime-versioned/values.yaml`
   - For latest releases: `charts/mini-runtime/values.yaml` stays as `latest`

3. **Commit and push** to trigger GitHub Actions:
   ```bash
   git add charts/mini-runtime*
   git commit -m "Release mini-runtime charts v0.5.9"
   git push origin master
   ```

4. Your existing GitHub Actions workflow will automatically:
   - Package all three charts
   - Publish to GitHub Pages
   - Update the Helm repository index

### How It Works

**Local Development:**
- Uses `repository: file://../mini-runtime-base` in Chart.yaml
- Runs `helm dependency update` to link to local base chart
- Works perfectly for testing

**Published to Registry:**
- Users run: `helm repo add akto https://akto-api-security.github.io/helm-charts`
- When installing mini-runtime or mini-runtime-versioned, Helm automatically:
  - Finds the base chart dependency in the same repo
  - Downloads and uses it

### User Installation

Users can now choose between two charts:

```bash
# Add the repo once
helm repo add akto https://akto-api-security.github.io/helm-charts
helm repo update

# Install with latest tags
helm install my-runtime akto/akto-mini-runtime

# OR install with versioned tags
helm install my-runtime akto/akto-mini-runtime-versioned
```

## Maintenance

### For Feature Changes
1. Update only `charts/mini-runtime-base/templates/` or `charts/mini-runtime-base/values.yaml`
2. Bump version in all three Chart.yaml files
3. Commit and push

### For Version Tag Updates
1. Update only `charts/mini-runtime-versioned/values.yaml` with new image versions
2. Bump version in all three Chart.yaml files (or just mini-runtime-versioned if only that changed)
3. Commit and push

### Version Sync
Keep these versions in sync across all three charts:
- `mini-runtime-base/Chart.yaml` version X.Y.Z
- `mini-runtime/Chart.yaml` version X.Y.Z and dependency version X.Y.Z
- `mini-runtime-versioned/Chart.yaml` version X.Y.Z and dependency version X.Y.Z

## Testing Before Publishing

Always test locally before pushing:

```bash
# Test mini-runtime with latest tags
cd charts/mini-runtime
helm dependency update
helm template test . | grep "image:"

# Test mini-runtime-versioned with versioned tags
cd charts/mini-runtime-versioned
helm dependency update
helm template test . | grep "image:"

# Verify all images show correct tags
```

Expected output:
- **mini-runtime**: All images should show `:latest`
- **mini-runtime-versioned**: All images should show specific versions
