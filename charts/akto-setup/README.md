# Akto setup

You can install Akto via Helm charts. 

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find Akto on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)

## Steps 
Here are the steps to install Akto via Helm charts - 

1. Prepare Mongo Connection string
2. Install Akto via Helm
3. Verify Installation and harden security

### Create Mongo instance
Akto Helm setup needs a Mongo connection string as input. It can come from either of the following -
1. **Your own Mongo**
   Ensure your machine where you setup Mongo is NOT exposed to public internet. It shouldn't have a public IP. You can setup Mongo by running the following commands.
   ```
   sudo yum update -y
   sudo yum install -y docker
   sudo dockerd&
   docker run --name mongo --restart always -v ./data:/data/db -p 27017:27017 mongo
   sudo systemctl enable /usr/lib/systemd/system/docker.service
   ```
   <img width="1161" alt="AWS EC2 Mongo" src="https://github.com/akto-api-security/Documentation/assets/91221068/0b6b87e8-9797-4729-ab01-fd48f99efbd3">

   The connection string would then be `mongodb://<YOUR_INSTANCE_PRIVATE_IP>:27017/admini`
2. **Mongo Atlas**
   You can use Mongo Atlas connection as well
   1. Go to `Database Deployments` page for your project
   2. Click on `Connect` button
   3. Choose `Connect your application` option
   4. Copy the connection string. It should look like `mongodb://....`
      <img width="567" alt="Mongo Atlas" src="https://github.com/akto-api-security/Documentation/assets/91221068/1128e098-3618-4d19-b9c3-2c7482b4714e">

3. **AWS Document DB**
   If you are on AWS, you can use AWS Document DB too. You can find the connection string on the Cluster page itself.
   <img width="1399" alt="AWS DocDB" src="https://github.com/akto-api-security/Documentation/assets/91221068/4ce4d84d-6e8a-4d4d-bc0b-e5d03e3f824a">

Note: Please ensure your K8S cluster has connectivity to Mongo. 

### Install Akto via Helm

#### Option 1: Install from Akto Helm Repository

1. Add Akto repo
   ```bash
   helm repo add akto https://akto-api-security.github.io/helm-charts
   ```
2. Install Akto via helm
   ```bash
   helm install akto akto/akto -n akto --create-namespace --set mongo.aktoMongoConn="<AKTO_CONNECTION_STRING>"
   ```

#### Option 2: Install from Local Chart

1. Basic installation
   ```bash
   helm install akto charts/akto-setup \
     --namespace akto \
     --create-namespace \
     --set mongo.aktoMongoConn="<AKTO_CONNECTION_STRING>"
   ```

2. Installation with custom values file
   ```bash
   helm install akto charts/akto-setup \
     -f charts/akto-setup/client_custom_value.yaml \
     --namespace akto \
     --create-namespace
   ```

3. Installation with specific Keel namespace configuration
   ```bash
   helm install akto charts/akto-setup \
     -f charts/akto-setup/client_custom_value.yaml \
     --namespace akto \
     --set keel.keel.env.watchNamespaces="akto" \
     --create-namespace
   ```

4. Run `kubectl get pods -n akto` and verify you can see 5 pods (mongo, dashboard, runtime, testing, keel)
   ```bash
   kubectl get pods -n akto
   ```
   <img width="862" alt="Screenshot 2023-11-16 at 10 08 23 AM" src="https://github.com/akto-api-security/Documentation/assets/91221068/3a5a4d26-3305-4eb2-94f9-ae598817252d">

### Verify Installation and harden security

1. Run the following to get Akto dashboard url
   ```bash
   kubectl get services/akto-dashboard -n akto | awk -F " " '{print $4;}'
   ```
2. Open Akto dashboard on port 8080. eg `http://a54b36c1f4asdaasdfbd06a259de2-acf687643f6fe4eb.elb.ap-south-1.amazonaws.com:8080/`

3. Verify Keel is running with minimal permissions
   ```bash
   # Check Keel logs for errors
   kubectl logs -n akto -l app=akto-keel --tail=50

   # Verify NAMESPACES configuration
   kubectl get pod -n akto -l app=akto-keel -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="NAMESPACES")].value}'

   # Check ClusterRole permissions
   kubectl describe clusterrole akto-keel
   ```

4. For good security measures, you should enable HTTPS by adding a certificate and put it behind a VPN. If you are on AWS, follow the guide [here](https://docs.akto.io/getting-started/aws-ssl).

## Keel Configuration

Keel automatically monitors and updates container images when new versions are available.

### Keel Security Features

This chart includes **minimal RBAC permissions** for Keel:

**✅ Allowed:**
- Read access (`get`, `watch`, `list`) - cluster-wide
- Update access (`update`, `patch`) - restricted by `NAMESPACES` env var
- Resources: **pods, deployments only**

**❌ Restricted:**
- No `delete` permission
- No `create` permission
- No namespace listing
- No port-forward capability
- No access to secrets, configmaps, statefulsets, daemonsets, cronjobs, replicasets, replicationcontrollers, jobs

### Configure Watched Namespaces

By default, Keel watches only the namespace where it's deployed. You can customize this:

**Watch single namespace:**
```bash
helm install akto charts/akto-setup \
  --set keel.keel.env.watchNamespaces="akto" \
  --namespace akto
```

**Watch multiple namespaces:**
```bash
helm install akto charts/akto-setup \
  --set keel.keel.env.watchNamespaces="akto,production,staging" \
  --namespace akto
```

**Disable Keel:**
```bash
helm install akto charts/akto-setup \
  --set keel.keel.env.enabled=false \
  --namespace akto
```

## Upgrading

```bash
helm upgrade akto charts/akto-setup \
  -f charts/akto-setup/client_custom_value.yaml \
  --namespace akto
```

## Troubleshooting

### Check Keel Permission Errors
```bash
kubectl logs -n akto -l app=akto-keel --tail=100 | grep -i "forbidden\|error"
```

### Verify All Components
```bash
kubectl get all -n akto
```
