# 5. Get the CCE kubeconfig for Jenkins

1. Console → **CCE → your cluster → Overview → Connection Information → kubectl → Configure**.
2. Choose the **Intranet (internal) access** kubeconfig. Jenkins runs inside the VPC, so it doesn't need an EIP on the API server.
3. Choose a long validity period, for example 5 years or the maximum allowed. Note the expiry date in your calendar.
4. Download `kubeconfig.json`.

## Test it on the Jenkins VM first
```bash
scp -i ~/.ssh/sky47-beta.pem kubeconfig.json root@<EIP>:/tmp/kubeconfig.json
ssh root@<EIP>
sudo chown jenkins /tmp/kubeconfig.json
sudo -u jenkins kubectl --kubeconfig /tmp/kubeconfig.json get ns sample-app
sudo -u jenkins kubectl --kubeconfig /tmp/kubeconfig.json -n sample-app get deploy
#   NAME             READY
#   backend          1/1
#   orders-backend   1/1
#   frontend         1/1
sudo KUBECONFIG_FILE=/tmp/kubeconfig.json bash scripts/verify.sh
sudo rm /tmp/kubeconfig.json      # Jenkins keeps its own copy as a credential
```

If kubectl hangs or times out, the network is blocking it. See [08-troubleshooting.md](08-troubleshooting.md#kubectl-timeout).

## Upload it to Jenkins
Go to **Manage Jenkins → Credentials → Add**:
- Kind: **Secret file**
- File: `kubeconfig.json`
- ID: `cce-kubeconfig`

## What the cluster must already have
The pipeline only **updates images** on Deployments that already exist. It doesn't create the namespace, the secrets or the services. That one-time cluster setup is in the app repo's `K8S-DEPLOYMENT.md` §5 to §7:
- namespace `sample-app`
- `default-secret`, the pull secret for SWR
- `mysql-secret`, the DB credentials
- Deployments and Services `backend`, `orders-backend`, `frontend` (from `k8s/*.yaml`)

## Least privilege (recommended now)
The console kubeconfig carries all of the IAM user's cluster permissions, and builds run on the Jenkins server ([09-security-model.md](09-security-model.md)). Give Jenkins a ServiceAccount that can only do what the pipeline needs in `sample-app`.

Apply this once, as a cluster admin, from a machine with the console kubeconfig:
```yaml
# jenkins-deployer.yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: jenkins-deployer, namespace: sample-app }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: jenkins-deployer, namespace: sample-app }
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "patch", "update"]
  - apiGroups: ["apps"]
    resources: ["replicasets", "controllerrevisions"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: jenkins-deployer, namespace: sample-app }
subjects: [{ kind: ServiceAccount, name: jenkins-deployer, namespace: sample-app }]
roleRef: { kind: Role, name: jenkins-deployer, apiGroup: rbac.authorization.k8s.io }
---
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-deployer-token
  namespace: sample-app
  annotations: { kubernetes.io/service-account.name: jenkins-deployer }
type: kubernetes.io/service-account-token
```
Build a kubeconfig from the ServiceAccount token. This reuses the server and CA from the console kubeconfig:
```bash
kubectl apply -f jenkins-deployer.yaml
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
TOKEN=$(kubectl -n sample-app get secret jenkins-deployer-token -o jsonpath='{.data.token}' | base64 -d)

KUBECONFIG=jenkins-kubeconfig kubectl config set-cluster cce --server="$SERVER" --certificate-authority=ca.crt --embed-certs=true
KUBECONFIG=jenkins-kubeconfig kubectl config set-credentials jenkins-deployer --token="$TOKEN"
KUBECONFIG=jenkins-kubeconfig kubectl config set-context jenkins --cluster=cce --user=jenkins-deployer --namespace=sample-app
KUBECONFIG=jenkins-kubeconfig kubectl config use-context jenkins

KUBECONFIG=jenkins-kubeconfig kubectl -n sample-app get deploy      # works
KUBECONFIG=jenkins-kubeconfig kubectl get nodes                     # Forbidden, as intended
rm ca.crt
```
Upload `jenkins-kubeconfig` as the `cce-kubeconfig` Secret file, replacing the console one, then delete the local copy. The token doesn't expire. To revoke it, delete the `jenkins-deployer-token` Secret.
