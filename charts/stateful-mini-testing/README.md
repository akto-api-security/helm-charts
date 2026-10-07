# Akto stateful mini-testing

Runs the Akto testing module in your Kubernetes cluster as a StatefulSet, connected to a Kafka broker that uses SASL.

## How it works

- **Stable pod names:** pods are named `akto-external-testing-0`, `-1`, and so on. A pod keeps its name when it restarts.
- **One volume per pod:** each pod saves the state of its current test run in `/app/testing-info`. The chart creates a PersistentVolumeClaim (PVC) for every pod (100Mi by default). Pods never share a volume.
- **Kafka runs separately:** the queue of test messages and the progress of each run live in a Kafka broker outside the testing pod. The pod connects to it using SASL.
- **Restarts are safe:** a restarted pod re-attaches to its own volume, reconnects to Kafka and continues the run where it stopped.
- Volumes are not deleted when you scale down or uninstall, so no data is lost by accident.

## Before you start

1. A Kubernetes cluster where you can deploy, and [`helm`](https://helm.sh/docs/intro/install/) installed.
2. A default storage class that can create volumes (most managed clusters have one).
3. A Kafka broker with SASL enabled that the pod can reach. Use one that stores its data on a persistent volume. You need its address, the SASL mechanism (`PLAIN`, `SCRAM-SHA-256` or `SCRAM-SHA-512`), and a username and password.
4. Your `AKTO_TOKEN`, found in the Akto dashboard under quick start > hybrid saas. See the [docs](https://docs.akto.io/traffic-connections/traffic-data-sources/hybrid-saas).

## Install

1. Create a secret with the Kafka username and password:

```bash
kubectl create secret generic kafka-sasl-credentials -n <NAMESPACE> \
  --from-literal=username=<KAFKA_USERNAME> \
  --from-literal=password=<KAFKA_PASSWORD>
```

2. Install the chart:

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts

helm install akto-stateful-mini-testing akto/akto-stateful-mini-testing -n <NAMESPACE> \
  --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>" \
  --set testing.aktoApiSecurityTesting.env.kafkaBrokerUrl="<KAFKA_HOST>:<KAFKA_PORT>" \
  --set testing.kafka1.env.saslMechanism="SCRAM-SHA-512" \
  --set testing.kafka1.env.useSecretsForSaslCredentials=true \
  --set testing.kafka1.env.saslCredentialsSecrets.existingSecret="kafka-sasl-credentials"
```

3. Check that it is running:

```bash
kubectl get pods -n <NAMESPACE>   # akto-external-testing-0 is Running
kubectl get pvc -n <NAMESPACE>    # testing-info-akto-external-testing-0 is Bound
```

## Database Abstractor Token

By default the token is passed with `--set testing.aktoApiSecurityTesting.env.databaseAbstractorToken=<AKTO_TOKEN>`. You can use a Kubernetes secret instead:

| Option | Flags |
|---|---|
| A secret you created (recommended). Key: `token` | `--set testing.aktoApiSecurityTesting.env.useSecretsForDatabaseAbstractorToken=true --set testing.aktoApiSecurityTesting.env.databaseAbstractorTokenSecrets.existingSecret=<SECRET>` |
| Pass the token directly | `--set testing.aktoApiSecurityTesting.env.databaseAbstractorToken=<AKTO_TOKEN>` |

## Kafka credentials

Pick one way to give the testing module the Kafka username and password:

| Option | Flags |
|---|---|
| A secret you created (recommended). Keys: `username`, `password` | `--set testing.kafka1.env.useSecretsForSaslCredentials=true --set testing.kafka1.env.saslCredentialsSecrets.existingSecret=<SECRET>` |
| Pass the values directly | `--set testing.kafka1.env.saslUsername=<USER> --set testing.kafka1.env.saslPassword=<PASSWORD>` |

The default mechanism is `SCRAM-SHA-512`. Change it with `testing.kafka1.env.saslMechanism`. If your Kafka does not use SASL, set `testing.kafka1.useSasl=false`.

## Options

| Goal | Flag |
|---|---|
| Run more than one testing pod | `--set testing.replicas=<COUNT>` |
| Run multiple tests in parallel | `--set testing.aktoApiSecurityTesting.env.concurrentTesting=true` |
| Use a specific storage class | `--set testing.persistence.storageClass=<STORAGE_CLASS>` |
| Change the volume size (default `100Mi`) | `--set testing.persistence.size=<SIZE>` |
| Use a proxy | `--set tokens.env.proxyUri="<PROXY_URI>" --set tokens.env.noProxy="<NO_PROXY_URLS>"` |

## Uninstall

```bash
helm uninstall akto-stateful-mini-testing -n <NAMESPACE>
```

The volumes are kept. To delete them too:

```bash
kubectl delete pvc -n <NAMESPACE> -l app=<RELEASE_NAME>-akto-stateful-mini-testing
```

## Troubleshooting

| Problem | What to check |
|---|---|
| Pod stays `Pending` | `kubectl describe pvc -n <NAMESPACE>`. There is probably no default storage class. |
| Cannot connect to Kafka | Check `kafkaBrokerUrl` and that the pod can reach the broker. |
| `SaslAuthenticationException` in the logs | The username, password or mechanism does not match the broker. |
| `CreateContainerConfigError` | The secret in `existingSecret` is missing or lacks a key (`username` and `password` for Kafka, `token` for the token). |
| Run stays at 0% after a restart | Kafka lost its data. Use a Kafka with a persistent volume. |

## Support

Email `help@akto.io` or join our [discord](https://www.akto.io/community).
