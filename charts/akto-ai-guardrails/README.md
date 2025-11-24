# Akto AI Guardrails Helm Chart

This Helm chart deploys the Akto AI Guardrails services on Kubernetes.

## Overview

The Akto AI Guardrails solution consists of three microservices:

1. **Agent Guard Executor** (Python Service): ML model service for AI guardrail execution
2. **Agent Guard Engine** (Go Service): Orchestration service that coordinates requests
3. **Guardrails Service**: Main service that integrates with Akto's backend services

## Architecture

```
┌─────────────────────┐
│ Guardrails Service  │
│     (Port 8080)     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Agent Guard Engine  │
│     (Port 8091)     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Agent Guard Executor│
│     (Port 8092)     │
└─────────────────────┘
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support (for model cache persistence)
- 8GB+ available memory (recommended)
- 4+ CPU cores (recommended)

## Installation

### Quick Start

```bash
# Add the Akto Helm repository (if available)
helm repo add akto https://charts.akto.io
helm repo update

# Install with default values
helm install akto-ai-guardrails akto/akto-ai-guardrails
```

### Install from local chart

```bash
# From the helm-charts directory
helm install akto-ai-guardrails ./charts/akto-ai-guardrails
```

### Custom Installation

Create a custom values file with your configuration:

```bash
# Create custom-values.yaml
cat <<EOF > custom-values.yaml
# Configure required backend services
guardrailsService:
  env:
    aktoApiBaseUrl: "https://your-akto-api.example.com"
    databaseAbstractorServiceUrl: "https://your-database-abstractor.example.com"
    databaseAbstractorServiceToken: "your-jwt-token-here"
    threatBackendUrl: "https://your-threat-backend.example.com"
    threatBackendToken: "your-jwt-token-here"

# Adjust resources based on your cluster
agentGuardExecutor:
  resources:
    requests:
      memory: 4Gi
      cpu: 2
    limits:
      memory: 8Gi
      cpu: 4

# Configure persistence
agentGuardExecutor:
  persistence:
    size: 30Gi
    storageClass: "fast-ssd"
EOF

# Install with custom values
helm install akto-ai-guardrails ./charts/akto-ai-guardrails -f custom-values.yaml

# IMPORTANT: Add custom-values.yaml to .gitignore to avoid committing secrets
echo "custom-values.yaml" >> .gitignore
```

## Configuration

### Required Environment Variables

The following environment variables **must be configured** before deployment:

| Variable | Description | Required |
|----------|-------------|----------|
| `guardrailsService.env.aktoApiBaseUrl` | Base URL for Akto API | Yes |
| `guardrailsService.env.databaseAbstractorServiceUrl` | URL for database abstractor service | Yes |
| `guardrailsService.env.databaseAbstractorServiceToken` | JWT authentication token for database abstractor | Yes |
| `guardrailsService.env.threatBackendUrl` | URL for threat backend service | Yes |
| `guardrailsService.env.threatBackendToken` | JWT authentication token for threat backend | Yes |

**Note**: These values are empty by default in `values.yaml` for security reasons. You must provide them via:
- A custom values file (recommended for development)
- Helm `--set` flags
- Kubernetes secrets (recommended for production)

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `agentGuardExecutor.enabled` | Enable the Python executor service | `true` |
| `agentGuardExecutor.replicas` | Number of executor replicas | `1` |
| `agentGuardExecutor.persistence.enabled` | Enable persistent volume for model cache | `true` |
| `agentGuardExecutor.persistence.size` | Size of model cache PVC | `20Gi` |
| `agentGuardEngine.enabled` | Enable the Go engine service | `true` |
| `agentGuardEngine.replicas` | Number of engine replicas | `1` |
| `guardrailsService.enabled` | Enable the guardrails service | `true` |
| `guardrailsService.env.databaseAbstractorServiceUrl` | Database abstractor URL | `""` |
| `guardrailsService.env.threatBackendUrl` | Threat backend URL | `""` |

### Resource Configuration

The default resource allocations are:

**Agent Guard Executor (Python)**:
- Requests: 2 CPU, 2Gi memory
- Limits: 4 CPU, 6Gi memory

**Agent Guard Engine (Go)**:
- Requests: 500m CPU, 1Gi memory
- Limits: 2 CPU, 2Gi memory

**Guardrails Service**:
- Requests: 500m CPU, 1Gi memory
- Limits: 2 CPU, 2Gi memory

## Service Dependencies

The services are deployed in order with proper health checks:

1. **Agent Guard Executor** starts first and downloads ML models
2. **Agent Guard Engine** starts after executor is ready
3. **Guardrails Service** can be accessed once all services are healthy

## Persistent Storage

The Agent Guard Executor requires persistent storage to cache ML models. This prevents re-downloading models on pod restarts.

### Storage Classes

Specify a storage class in your values:

```yaml
agentGuardExecutor:
  persistence:
    storageClass: "gp3"  # AWS
    # storageClass: "standard-rwo"  # GCP
    # storageClass: "managed-premium"  # Azure
```

## Service Access

### Internal Service DNS

Services are accessible within the cluster at:

- `akto-ai-guardrails-executor:8092` - Executor service
- `akto-ai-guardrails-engine:8091` - Engine service
- `akto-ai-guardrails-service:8080` - Guardrails service

### External Access

To expose services externally, modify the service type:

```yaml
guardrailsService:
  service:
    type: LoadBalancer  # or NodePort
```

## Health Checks

All services include:
- **Liveness probes**: Restart unhealthy pods
- **Readiness probes**: Route traffic only to ready pods

The Python executor has longer initial delays to account for model loading time.

## Upgrading

```bash
# Upgrade to a new version
helm upgrade akto-ai-guardrails ./charts/akto-ai-guardrails -f custom-values.yaml

# Rollback if needed
helm rollback akto-ai-guardrails
```

## Uninstalling

```bash
# Remove the chart
helm uninstall akto-ai-guardrails

# Note: PVCs are not deleted automatically. Delete manually if needed:
kubectl delete pvc akto-ai-guardrails-model-cache
```

## Troubleshooting

### Pod Not Starting

Check pod status:
```bash
kubectl get pods -l app.kubernetes.io/name=akto-ai-guardrails
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Model Download Issues

The executor pod may take 5-10 minutes on first start to download ML models. Monitor logs:

```bash
kubectl logs -f deployment/akto-ai-guardrails-executor
```

### Resource Constraints

If pods are OOMKilled or CPU throttled, increase resource limits:

```yaml
agentGuardExecutor:
  resources:
    limits:
      memory: 8Gi  # Increase from default 6Gi
      cpu: 6       # Increase from default 4
```

### Service Connectivity

Test service connectivity:

```bash
# From within the cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- sh
curl http://akto-ai-guardrails-executor:8092/health
curl http://akto-ai-guardrails-engine:8091/health
curl http://akto-ai-guardrails-service:8080/health
```

## Security

### Pod Security

The chart includes security contexts:
- Non-root user execution
- Dropped capabilities
- Read-only root filesystem where possible

### Secrets Management

**IMPORTANT**: Never commit JWT tokens to version control. Use one of the following methods:

#### Method 1: Custom Values File (Development/Testing)

```bash
# Create a custom values file (add to .gitignore)
cat <<EOF > custom-values.yaml
guardrailsService:
  env:
    aktoApiBaseUrl: "https://akto-mcp-proxy-nginx.billing-53a.workers.dev"
    databaseAbstractorServiceUrl: "https://cyborg.akto.io"
    databaseAbstractorServiceToken: "your-jwt-token-here"
    threatBackendUrl: "https://tbs.akto.io"
    threatBackendToken: "your-jwt-token-here"
EOF

# Install with custom values
helm install akto-ai-guardrails ./charts/akto-ai-guardrails -f custom-values.yaml -n akto-ai

# Add to .gitignore
echo "custom-values.yaml" >> .gitignore
```

#### Method 2: Helm --set Flags (CI/CD)

```bash
helm install akto-ai-guardrails ./charts/akto-ai-guardrails -n akto-ai \
  --set guardrailsService.env.aktoApiBaseUrl="https://akto-mcp-proxy-nginx.billing-53a.workers.dev" \
  --set guardrailsService.env.databaseAbstractorServiceUrl="https://cyborg.akto.io" \
  --set guardrailsService.env.databaseAbstractorServiceToken="your-jwt-token" \
  --set guardrailsService.env.threatBackendUrl="https://tbs.akto.io" \
  --set guardrailsService.env.threatBackendToken="your-jwt-token"
```

#### Method 3: Kubernetes Secrets (Production - Recommended)

```bash
# Create secret with tokens
kubectl create secret generic guardrails-secrets -n akto-ai \
  --from-literal=database-abstractor-token='your-jwt-token' \
  --from-literal=threat-backend-token='your-jwt-token'

# Note: Using secrets requires modifying the deployment template to reference the secret
# This is the most secure approach for production environments
```

## Support

For issues and questions:
- GitHub: https://github.com/akto-api-security/helm-charts
- Documentation: https://www.akto.io/docs
- Email: support@akto.io

## License

Copyright © 2024 Akto
