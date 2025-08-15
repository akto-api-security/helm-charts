# Akto setup

You can install Akto via Helm charts. 

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find Akto mini-testing module on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto-mini-testing).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)

## Dependencies
If you don't need auto-scaling, skip this section.

Otherwise, if auto-scaling needs to be enabled to allow parallel test runs via multiple k8s pods, we need to install few dependencies via helm charts. 
1. Install `kube-prometheus-stack`
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
    
helm install prometheus prometheus-community/kube-prometheus-stack \
	--namespace <NAMESPACE> \
	--create-namespace
```
2. Install `keda`
```
helm repo add kedacore https://kedacore.github.io/charts  
helm repo update kedacore

helm install keda kedacore/keda \
  --namespace <NAMESPACE> \
  --create-namespace
```
3. Upgrade `keda` to set `watchNamespace`
```
helm upgrade keda kedacore/keda \
  --namespace <NAMESPACE> \
  --set watchNamespace=<NAMESPACE>
```
  - This restricts keda to watch/control only specific namespace(s)
  - Its fine if you get this error - `Error: UPGRADE FAILED: no RoleBinding with the name "keda-operator" found`
  - As a fix, re-run the helm upgrade command mentioned above, as the first run would create the `keda-operator` deployment in k8s.

4. While installing / upgrading Akto's helm chart (covered in later sections) additionally set the following flag
```
--set testing.autoScaling.enabled=true
```

## Steps 
Here are the steps to install Akto mini-testing via Helm charts - 

### Collect the env variables needed to install mini-testing

1. AKTO_TOKEN : You'll find this token in akto saas dashboard under quick start > hybrid saas . To see the complete docs, visit https://docs.akto.io/traffic-connections/traffic-data-sources/hybrid-saas .
2. PROXY_URI, NO_PROXY_URLS: Proxy variables to be used if internet connectivity is behind a proxy, skip these variables.

### Install Akto via Helm

1. Add Akto repo
   ```helm repo add akto https://akto-api-security.github.io/helm-charts```
2. Install Akto via helm
   ```bash
   helm install akto-mini-testing akto/akto-mini-testing -n <NAMESPACE> \
    --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>"
   ```
   ```bash
   helm install akto-mini-testing akto/akto-mini-testing -n <NAMESPACE> \
    --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>" \
    --set tokens.env.proxyUri="<PROXY_URI>" \
    --set tokens.env.noProxy="<NO_PROXY_URLS>"
   ```
   In order to enable auto-scaling, add the following flag
   ```
   --set testing.autoScaling.enabled=true
   ```
3. Run `kubectl get pods -n <NAMESPACE>` and verify you can see 1 mini-testing pod with 4 containers and 1 keel pod.

### Upgrading to new version

1. Update helm repo
   ```helm repo update akto```
2. Check the latest version for mini-testing module
   ```helm show chart akto/akto-mini-testing```
3. Upgrade
   ```bash
   helm upgrade akto-mini-testing akto/akto-mini-testing -n <namespace> --version <latest-version> \
    --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>
   ```
4. In order to enable auto-scaling, add the following flag to upgrade command.
   ```
   --set testing.autoScaling.enabled=true
   ```

## Get Support for your Akto setup

There are multiple ways to request support from Akto. We are 24X7 available on the following:

1. In-app `intercom` support. Message us with your query on intercom in Akto dashboard and someone will reply.
2. Join our [discord channel](https://www.akto.io/community) for community support.
3. Contact `help@akto.io` for email support.
4. Contact us [here](https://www.akto.io/contact-us).