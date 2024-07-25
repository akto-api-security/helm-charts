
## Akto - nginx module

A Helm chart for deploying Nginx with akto module and a sample application.

To install run the following command from the root directory.

Before installing change the values of `namespace` and `kafkaIP` in [values.yaml](./values.yaml) file accordingly.

```bash
helm install akto-nginx charts/nginx -n dev3
```