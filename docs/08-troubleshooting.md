# 8. Troubleshooting

Start with `sudo bash scripts/verify.sh`. It tells you which layer is broken.

## Jenkins won't start
- `journalctl -u jenkins -n 200`
- **"failed to find a valid Java installation"**: Java is missing or older than 21. Run `scripts/01-install-java.sh`, then `systemctl restart jenkins`.
- **Port already in use**: change `JENKINS_PORT` in `config/jenkins.env`, then run `scripts/02-install-jenkins.sh` again.
- Out of memory: lower `-Xmx` in `JENKINS_JAVA_OPTS`, or give the VM more RAM.

## `apt-get update`: NO_PUBKEY for pkg.jenkins.io
The signing key was rotated. See [07-operations.md](07-operations.md#signing-key-rotation).

## `permission denied ... /var/run/docker.sock`
The `jenkins` user isn't in the `docker` group yet, or Jenkins hasn't restarted since it was added.
```bash
sudo usermod -aG docker jenkins && sudo systemctl restart jenkins
```

## `docker build` fails pulling base images
The VM has no outbound internet. Bind an EIP or add a NAT gateway with an SNAT rule ([01-vm-provisioning.md](01-vm-provisioning.md#outbound-internet-required)). Docker Hub also limits anonymous pulls. If you hit that limit, add a Docker Hub login, or mirror the base images into SWR.

## SWR push: `unauthorized` / `denied`
- The username format is wrong. It must be `pk-isb-1_<domain>@<AK>`, with the region prefix and an underscore.
- The login key was generated from a different AK/SK pair, or the AK was deleted.
- The IAM user has no push permission on the org `pk-beta-repo`. Fix it under SWR → Organization → Permissions.
- You used the temporary 24-hour command. Switch to the long-term key ([04-credentials.md](04-credentials.md)).

## kubectl timeout
The error looks like `Unable to connect to the server: dial tcp 10.x.x.x:5443: i/o timeout`.
- Make sure you downloaded the **internal** kubeconfig, not the external (EIP) one.
- The Jenkins VM must be in the **same VPC** as CCE, or in a peered VPC.
- The CCE control-plane security group must allow 5443/tcp from the Jenkins VM's IP.
- Run `sudo -u jenkins kubectl --kubeconfig <file> cluster-info -v=6` to see where it stops.

## kubectl: `Forbidden`
The IAM user behind the kubeconfig has no CCE RBAC on `sample-app`. Fix it under CCE → Permissions.

## Rollout stuck, then auto-rolled back
```bash
kubectl -n sample-app describe deploy <svc>
kubectl -n sample-app get pods
kubectl -n sample-app describe pod <new-pod>      # Events at the bottom
kubectl -n sample-app logs <new-pod>
```
- **ImagePullBackOff**: `default-secret` is missing in `sample-app`, or the tag wasn't pushed.
- **CrashLoopBackOff**: check the app logs. Usually it's the DB connection (`mysql-secret`, `DB_HOST`) or the schema.
- **Readiness probe failing**: check `/api/health` (backend) and `/orders-api/health` (orders-backend).

## Job shows "Build Now" instead of "Build with Parameters"
Run it once so the parameters get registered ([jobs/...](../jobs/sample-project-sky-47-deploy.md#first-run-registers-the-parameters)).

## `No such DSL method 'ansiColor' / 'timestamps' / 'cleanWs'`
A plugin is missing. Run `sudo bash scripts/05-install-plugins.sh` again.
