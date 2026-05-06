# Akto AWS API Gateway Connector

Helm chart to run the **Akto API Gateway connector** on EKS. The connector reads API Gateway traffic from AWS CloudWatch Logs and sends it to Akto (Kafka + Cyborg).

**Prerequisites:** EKS cluster, `kubectl` and `helm` installed, AWS CLI configured.

---

## Step 1: Choose or create a namespace

- **Use the same namespace as mini-runtime**  
  If Akto mini-runtime is already running in a namespace (e.g. `akto`), use that namespace when installing the chart so the connector can reach Kafka in the same namespace. No need to create it.

- **Use a new namespace**  
  Run the following (replace `akto` with the name you want). Use this same namespace in Step 2 (IAM trust policy) and Step 3 (Helm install).

  ```bash
  kubectl create namespace akto
  ```

---

## Step 2: Create IAM role and policy (IRSA)

Do this once in your AWS account. The connector pod uses this role to read CloudWatch Logs and call API Gateway (OpenAPI discovery).

### 2.1 Get EKS OIDC provider ID

- In **AWS Console** → **EKS** → your cluster → **Overview** → **Details**.
- Copy the **OpenID Connect provider URL** (e.g. `https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716EXAMPLE`).
- The **OIDC provider ID** is the part after `/id/` (e.g. `EXAMPLED539D4633E53DE1B716EXAMPLE`).
- Note your **AWS Region**, **AWS Account ID**, and the **namespace** you will use (e.g. `akto`).

### 2.2 Create IAM policy

- Go to **IAM** → **Policies** → **Create policy**.
- Open the **JSON** tab and paste the policy below.
- Replace `REGION` and `ACCOUNT_ID` with your region and account ID. For CloudWatch you can use `arn:aws:logs:REGION:ACCOUNT_ID:log-group:*` or restrict to specific log group ARNs.
- **Next** → name the policy (e.g. `ApiGatewayConnectorPolicy`) → **Create policy**.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:FilterLogEvents",
        "logs:GetLogEvents"
      ],
      "Resource": "arn:aws:logs:REGION:ACCOUNT_ID:log-group:*"
    },
    {
      "Effect": "Allow",
      "Action": ["apigateway:GET"],
      "Resource": [
        "arn:aws:apigateway:REGION::/restapis",
        "arn:aws:apigateway:REGION::/restapis/*",
        "arn:aws:apigateway:REGION::/apis",
        "arn:aws:apigateway:REGION::/apis/*"
      ]
    }
  ]
}
```

### 2.3 Create IAM role

- Go to **IAM** → **Roles** → **Create role**.
- **Trusted entity type:** Web identity.
- **Identity provider:** choose your EKS OIDC provider (e.g. `oidc.eks.REGION.amazonaws.com/id/OIDC_ID`).

  **If the EKS OIDC provider is not listed**, create it in the AWS Console first:
  - Go to **IAM** → **Identity providers** → **Add provider**.
  - **Provider type:** OpenID Connect.
  - **Provider URL:** use the OpenID Connect provider URL from **EKS** → your cluster → **Overview** → **Details**.
  - **Audience:** `sts.amazonaws.com` → **Add provider**. Then create the role again; the new provider will appear in the list.

- **Audience:** `sts.amazonaws.com` → **Next**.
- Attach the policy from 2.2 (e.g. `ApiGatewayConnectorPolicy`) → **Next**.
- Name the role (e.g. `akto-api-gateway-connector-eks-role`) → **Create role**.

### 2.4 Update role trust policy

- Open the role → **Trust relationships** → **Edit**.
- Replace the policy with the JSON below. Replace:
  - `ACCOUNT_ID` – your AWS account ID  
  - `REGION` – EKS region (e.g. `us-east-1`)  
  - `OIDC_ID` – OIDC provider ID from 2.1  
  - `NAMESPACE` – namespace where you will install the chart (e.g. `akto`)
- **Save**.
- Copy the **role ARN** (e.g. `arn:aws:iam::123456789012:role/akto-api-gateway-connector-eks-role`) for the Helm install.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com",
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:NAMESPACE:service-account-eks"
        }
      }
    }
  ]
}
```

---

## Step 3: Deploy the Helm chart

### 3.1 Add the Helm repo (if installing from repo)

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts/
helm repo update
```

### 3.2 Install with required values

Choose one of the following. Replace placeholders (role ARN, region, log group, Kafka broker, token) with your values.

**Option A — Install from chart source (clone the repo)**

1. Clone the repo and switch to the branch that contains this chart:

```bash
git clone https://github.com/akto-api-security/helm-charts.git
cd helm-charts
git checkout aws_apig_helm_chart
```

2. From the repo root, install the chart (token is read from a secret by default):

```bash
helm install akto-aws-api-gateway-connector ./charts/akto-aws-api-gateway-connector -n <your-namespace> \
  --set serviceAccount.roleArn=<your-role-arn> \
  --set env.awsRegion=<your-aws-region> \
  --set env.logGroupName=<your-log-group-name> \
  --set env.aktoKafkaBrokerMal=<your-kafka-broker> \
  --set env.databaseAbstractorTokenSecrets.token="<your-token>"
```

**Option B — Install from Helm repo**

1. Add the repo and update (see 3.1 if needed).
2. Install the chart (token is read from a secret by default):

```bash
helm install akto-aws-api-gateway-connector akto/akto-aws-api-gateway-connector -n <your-namespace> \
  --set serviceAccount.roleArn=<your-role-arn> \
  --set env.awsRegion=<your-aws-region> \
  --set env.logGroupName=<your-log-group-name> \
  --set env.aktoKafkaBrokerMal=<your-kafka-broker> \
  --set env.databaseAbstractorTokenSecrets.token="<your-token>"
```

To use an existing secret instead: add `--set env.databaseAbstractorTokenSecrets.existingSecret="<secret-name>"` (secret must have key `token`).

**Alternative: install using values.yaml**

Instead of `--set`, edit `values.yaml` with your values, then run (from the chart directory when using Option A, or from any directory when using Option B):

```bash
helm install akto-aws-api-gateway-connector ./charts/akto-aws-api-gateway-connector -n <your-namespace> -f values.yaml
```

(or with `akto/akto-aws-api-gateway-connector` when using the Helm repo).

**Required values (reference)**

| Value | Description |
|-------|-------------|
| `serviceAccount.roleArn` | IAM role ARN from Step 2 (IRSA). |
| `env.awsRegion` | AWS region (e.g. `ap-south-1`, `us-east-1`). |
| `env.logGroupName` | CloudWatch log group name (or comma-separated names). |
| `env.aktoKafkaBrokerMal` | Kafka broker address (e.g. from Akto mini-runtime). |
| `env.databaseAbstractorToken` | Token (when using direct value). By default the token is read from a secret; see below. |

**Database abstractor token (default: from secrets)**

By default the token is read from a Kubernetes Secret (`env.useSecretsForDatabaseAbstractorToken: true`). You must provide either:

- **Helm creates the secret:** Set `env.databaseAbstractorTokenSecrets.token` to the token value. Helm will create a Secret named `<release-name>-db-token` with key `token`, and the pod will read from it.
- **Use an existing secret:** Set `env.databaseAbstractorTokenSecrets.existingSecret` to the name of an existing Secret in the same namespace. That secret must have a key named `token` containing the database abstractor token.

Example (Helm-managed secret, default):

```bash
--set env.databaseAbstractorTokenSecrets.token="<your-token>"
```

Example (existing secret):

```bash
--set env.databaseAbstractorTokenSecrets.existingSecret="my-db-token-secret"
```

**You can also Create the secret separately, then use it in the main chart**

Create the secret in the same namespace with kubectl, then install the connector chart and point it at that secret.

1. **Create the secret** (secret must have key `token`):

   ```bash
   kubectl create secret generic my-db-token -n <your-namespace> --from-literal=token="<your-token>"
   ```

2. **Install the connector chart** and reference that secret:

   ```bash
   helm install akto-aws-api-gateway-connector ./charts/akto-aws-api-gateway-connector -n <your-namespace> \
     --set serviceAccount.roleArn=... \
     --set env.awsRegion=... \
     --set env.logGroupName=... \
     --set env.aktoKafkaBrokerMal=... \
     --set env.databaseAbstractorTokenSecrets.existingSecret="my-db-token"
   ```

   The secret must have a key named `token`; the connector deployment will use `secretKeyRef.key: token`.

**Optional — direct value instead of secret:** Set `env.useSecretsForDatabaseAbstractorToken=false` and `env.databaseAbstractorToken=<your-token>`. The token is then stored in the Deployment as a plain env var.

**Note:** If `logGroupName` contains commas (e.g. multiple log groups), Helm treats commas as separators. Escape each comma with a backslash: `\,`. Example: `--set 'env.logGroupName=log-group-1\,log-group-2'`.

### 3.3 Verify

```bash
kubectl get pods -n <your-namespace>
kubectl logs -f deployment/api-gateway-logging -n <your-namespace>
```

### 3.4 Upgrade or uninstall

**Upgrade (after changing values or chart):**

```bash
helm upgrade akto-aws-api-gateway-connector ./charts/akto-aws-api-gateway-connector -n <your-namespace> \
  --set serviceAccount.roleArn=<your-role-arn> \
  --set env.awsRegion=<your-aws-region> \
  --set env.logGroupName=<your-log-group-name> \
  --set env.aktoKafkaBrokerMal=<your-kafka-broker> \
  --set env.databaseAbstractorTokenSecrets.token="<your-token>"
```

**Uninstall:**

```bash
helm uninstall akto-aws-api-gateway-connector -n <your-namespace>
```
