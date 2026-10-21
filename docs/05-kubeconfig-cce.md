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

## Least privilege (recommended later)
The console kubeconfig gives the IAM user's full cluster permissions. To limit Jenkins to `sample-app` only:
- Create a ServiceAccount with a Role that can `get/list/patch/watch` Deployments, ReplicaSets and Pods in `sample-app`.
- Build a kubeconfig from that ServiceAccount's token.
- Store it as `cce-kubeconfig`.
