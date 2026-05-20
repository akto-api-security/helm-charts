# Akto setup

You can install Akto via Helm charts. 

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find Akto mini-runtime on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto-mini-runtime).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)

## Steps 
Here are the steps to install Akto mini-runtime via Helm charts - 

### Collect the env variables needed to install mini-runtime

1. AKTO_TOKEN : You'll find this token in akto saas dashboard under quick start > hybrid saas . To see the complete docs, visit https://docs.akto.io/traffic-connections/traffic-data-sources/hybrid-saas .

### Install Akto via Helm

1. Add akto helm repository.
   ```bash
   helm repo add akto https://akto-api-security.github.io/helm-charts/
   ```

2. Install akto-mini-runtime helm chart in your kubernetes cluster.

      1. Directly using database abstractor token

         ```bash
         helm install akto-mini-runtime akto/akto-mini-runtime -n <your-namespace> --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="<your-database-abstractor-token>"
         ```

      2. Storing the database abstractor token in a secret

         ```bash
         helm install akto-mini-runtime akto/akto-mini-runtime -n <your-namespace> --set mini_runtime.aktoApiSecurityRuntime.env.useSecretsForDatabaseAbstractorToken=true --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorTokenSecrets.token="<your-database-abstractor-token>"
         ```

3. Run `kubectl get pods -n <NAMESPACE>` and verify you can see 1 mini-runtime pod with 4 containers and 1 keel pod.

### Upgrading to new version

1. Update helm repo
   ```helm repo update```
2. Check the latest version for mini-testing module
   ```helm show chart akto/akto-mini-runtime```
3. Upgrade
   ```bash
   helm upgrade akto-mini-runtime akto/akto-mini-runtime -n <namespace> --version <latest-version> --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="<your-database-abstractor-token>"
   ```

## Configuring Annotations

You can add custom Kubernetes annotations to Service, Deployment, and Pod resources for all components. This is useful for integrating with monitoring systems, logging, or other Kubernetes-native tools.

### Annotation Keys

For each component (`mini_runtime`, `threat_client`, `keel`, `redis`), you can configure three types of annotations:

- `<component>.deploymentAnnotations` - Applied to Deployment metadata
- `<component>.podAnnotations` - Applied to Pod template metadata
- `<component>.serviceAnnotations` - Applied to Service metadata

### Examples

#### 1. Add Prometheus monitoring annotations to pods

```bash
helm install akto-mini-runtime akto/akto-mini-runtime \
  --set mini_runtime.podAnnotations."prometheus\.io/scrape"=true \
  --set mini_runtime.podAnnotations."prometheus\.io/port"=9090 \
  --set threat_client.podAnnotations."prometheus\.io/scrape"=true \
  --set threat_client.podAnnotations."prometheus\.io/port"=8080
```

#### 2. Add custom labels to deployment metadata

```bash
helm install akto-mini-runtime akto/akto-mini-runtime \
  --set mini_runtime.deploymentAnnotations."deployment\.kubernetes\.io/team"=platform \
  --set mini_runtime.deploymentAnnotations."deployment\.kubernetes\.io/component"=api-security
```

#### 3. Configure AWS load balancer annotations on services

```bash
helm install akto-mini-runtime akto/akto-mini-runtime \
  --set mini_runtime.serviceAnnotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set mini_runtime.serviceAnnotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internal
```

#### 4. Using values file

Alternatively, you can configure annotations in a `values.yaml` file:

```yaml
mini_runtime:
  deploymentAnnotations:
    app.example.com/version: "1.0"
    app.example.com/owner: "platform-team"
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
  serviceAnnotations:
    service.beta.kubernetes.io/aws-load-balancer-internal: "true"

threat_client:
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"

redis:
  podAnnotations:
    app.example.com/component: "cache"
```

Then install with:

```bash
helm install akto-mini-runtime akto/akto-mini-runtime -f values.yaml
```

### Keel Auto-Update Annotations

When Keel is enabled (`keel.keel.enabled=true`), deployment metadata annotations for `mini_runtime` and `threat_client` will automatically include Keel's update policy annotations. You can still add custom annotations alongside these managed annotations using `deploymentAnnotations`.

## Get Support for your Akto setup

There are multiple ways to request support from Akto. We are 24X7 available on the following:

1. In-app `intercom` support. Message us with your query on intercom in Akto dashboard and someone will reply.
2. Join our [discord channel](https://www.akto.io/community) for community support.
3. Contact `help@akto.io` for email support.
4. Contact us [here](https://www.akto.io/contact-us).