# Akto stateful mini-testing

Runs the Akto testing module in your Kubernetes cluster.

## How it works

This chart deploys the testing module as a Kubernetes **StatefulSet** instead of a regular Deployment. A StatefulSet gives every pod a stable identity: pods are named `akto-external-testing-0`, `akto-external-testing-1` and so on, and a pod keeps the same name when it restarts or moves to another node.

Each testing pod needs to remember its own information between restarts. It stores this as a `.json` file in a `testing-info` folder (`/app/testing-info`). To make that possible, the chart creates a **PersistentVolumeClaim (PVC) for every pod**:

- Each pod gets its own small volume (100Mi by default). Pods never share a volume.
- When a pod restarts, it re-attaches to the same volume and picks up its file, so it is not treated as a new testing module.
- If you run more pods (`testing.replicas`), each new pod gets its own new volume.
- Volumes are not deleted automatically when you scale down or uninstall, so no data is lost by accident. See [Uninstall](#uninstall) to remove them.

Your cluster needs a default storage class that can provision volumes. Most managed clusters (EKS, GKE, AKS) have one. To use a specific one, add `--set testing.persistence.storageClass=<STORAGE_CLASS>`. To change the volume size, add `--set testing.persistence.size=<SIZE>`.

## Before you start

1. A Kubernetes cluster where you can deploy
2. [`helm`](https://helm.sh/docs/intro/install/) installed
3. Your `AKTO_TOKEN`, found in the Akto dashboard under quick start > hybrid saas. See the [docs](https://docs.akto.io/traffic-connections/traffic-data-sources/hybrid-saas).

## Install

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts

helm install akto-stateful-mini-testing akto/akto-stateful-mini-testing -n <NAMESPACE> \
  --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>"
```

To run more than one testing pod, add `--set testing.replicas=<COUNT>`.

If you are behind a proxy, also add:

```bash
  --set tokens.env.proxyUri="<PROXY_URI>" \
  --set tokens.env.noProxy="<NO_PROXY_URLS>"
```

Check that it is running:

```bash
kubectl get pods -n <NAMESPACE>
```

You should see a testing pod named `akto-external-testing-0` in the `Running` state.

## Upgrade

```bash
helm repo update akto
helm upgrade akto-stateful-mini-testing akto/akto-stateful-mini-testing -n <NAMESPACE> \
  --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>"
```

## Uninstall

```bash
helm uninstall akto-stateful-mini-testing -n <NAMESPACE>
```

The saved data volumes are kept after uninstall. To delete them too:

```bash
kubectl delete pvc -n <NAMESPACE> -l app=<RELEASE_NAME>-akto-stateful-mini-testing
```

## Support

Email `help@akto.io` or join our [discord](https://www.akto.io/community).
