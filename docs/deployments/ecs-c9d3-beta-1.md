# Deployment log: ecs-c9d3-beta-1

Jenkins for sky47 CCE deploys, served at **https://jenkins.paykoko.pk**.

| | |
|---|---|
| Host | `ecs-c9d3-beta-1`, sky47 ECS, Ubuntu 24.04.4 LTS, 4 vCPU, 7 GB RAM, 3.7 GB swap (`/swap.img`), 24 GB root disk |
| Private IP | 10.10.1.250 |
| EIP | <EIP> |
| Settings | [`config/servers/ecs-c9d3-beta-1.env`](../../config/servers/ecs-c9d3-beta-1.env), copied to `config/jenkins.env` |
| Repo checkout used | `/home/ubuntu/beta-pk/jenkin-server-pk`, branch `beta-1-server-setup`; from step 9 on, `jenkins-casc-automation` |

## Starting state (2026-10-22)
- A local docker-compose copy of the app was running from `/home/ubuntu/beta-pk/sample-project-sky-47-deploy-test`. That directory no longer contains a compose file. Restart policy `no`.
  - `sample-project-sky-47-deploy-test-backend-1` on **:8080**
  - `sample-project-sky-47-deploy-test-frontend-1` on **:80**
- There were also two exited containers from an untagged image: `zen_hodgkin` and `charming_williamson`. They were left as they were.
- Docker was Ubuntu's `docker.io` 29.1.3 rather than Docker CE, with no buildx. `03-install-docker.sh` keeps the existing install, so builds use the legacy builder.
- kubectl v1.31.0 was already in `/usr/local/bin`.
- `/opt/jenkin-server-pk` is an older root-owned clone. Its `config/jenkins.env` has `KUBECTL_VERSION=v1.31`, which is invalid: the download needs the full version, so 04 would fail. It was **not** used.
- SWR and CCE access were already set up on the host by the operator.
- Swap and the timezone (UTC) were already fine, and ufw was not enabled.

## Steps

### 1. Repo changes (commit d6b939a)
- The weekly docker prune is now safe on a shared host: it removes dangling images and build cache only.
- New setting `JENKINS_LISTEN_ADDRESS` (Jenkins binds to 127.0.0.1 behind nginx).
- New script `scripts/08-tls-certbot.sh`.

### 2. Free ports 80/8080 (2026-10-22 03:12 UTC)
```bash
sudo docker stop sample-project-sky-47-deploy-test-backend-1 sample-project-sky-47-deploy-test-frontend-1
```
The containers and images are kept.

**To bring the local app back**, stop Jenkins and nginx first, because they hold 8080 and 80:
```bash
sudo docker start sample-project-sky-47-deploy-test-backend-1 sample-project-sky-47-deploy-test-frontend-1
```

### 3. Config
```bash
cp config/servers/ecs-c9d3-beta-1.env config/jenkins.env
```

### 4. Install
```bash
sudo bash scripts/bootstrap.sh
```
Started 03:12 UTC, finished 03:49 UTC. All steps OK:
- 00: prereqs. Swap and timezone were already fine.
- 01: OpenJDK 21.0.12.1.
- 02: **Jenkins 2.580.1 LTS**, systemd override with `JENKINS_LISTEN_ADDRESS=127.0.0.1`.
- 03: kept the existing docker.io 29.1.3, added `jenkins` to the `docker` group, installed the safer weekly prune.
- 04: kubectl v1.31.0.
- 05: plugin manager 2.15.0, **83 plugins** (exact versions in `/var/lib/jenkins/INSTALLED_PLUGINS.txt`).

Step 05 took about 32 minutes. The plugin manager kept logging `Network is unreachable` for some mirrors because Java tries IPv6 first and this VM has no IPv6 route. It falls back to IPv4, so this is harmless.

### 5. Verify (04:08 UTC)
`sudo bash scripts/verify.sh` reported **All checks passed**:
- service, Java, Docker for the jenkins user, kubectl
- network reach to Docker Hub, GitHub and SWR

The CCE and SWR-login checks were skipped because no credentials were passed in. `ss -ltnp` shows Jenkins on `127.0.0.1:8080` only.

### 6. nginx reverse proxy (04:08 UTC)
```bash
sudo bash scripts/06-nginx-reverse-proxy.sh
```
- nginx 1.24.0 listens on :80 with `server_name jenkins.paykoko.pk` and proxies to 127.0.0.1:8080.
- `curl -H 'Host: jenkins.paykoko.pk' http://127.0.0.1/login` returns 200 (`X-Jenkins: 2.580.1`).

### 7. DNS and security group (operator, sky47 console / DNS provider)
- [x] DNS: A record `jenkins.paykoko.pk` → `<EIP>`, TTL 300
- [x] Security group: inbound 80/tcp and 443/tcp from 0.0.0.0/0 (needed for Let's Encrypt HTTP-01 and renewals); remove 8080

At 04:09 UTC there was no DNS record yet. A request to http://<EIP>/ from the VM itself timed out, which could be the security group or the cloud network not routing a VM's traffic back to its own EIP.

By 04:38 UTC the operator had done both. `jenkins.paykoko.pk` resolved to <EIP> via 8.8.8.8 and 1.1.1.1, and `http://jenkins.paykoko.pk/login` returned 200 from the internet path.

### 8. HTTPS with Let's Encrypt (04:39 UTC)
```bash
sudo bash scripts/08-tls-certbot.sh     # CERTBOT_EMAIL from config/servers/ecs-c9d3-beta-1.env
```
- Certificate `CN=jenkins.paykoko.pk` from Let's Encrypt (issuer YE2), **expires 2027-01-20**. It renews automatically through `certbot.timer`, and `certbot renew --dry-run` succeeded.
- certbot added the 443 server block to `/etc/nginx/sites-enabled/jenkins`, plus a 301 redirect from HTTP to HTTPS.
- Checks:
  - `http://jenkins.paykoko.pk/login` returns 301 to `https://…`
  - `https://jenkins.paykoko.pk/login` returns 200 with a valid certificate chain
  - Listeners: nginx on :80 and :443, Jenkins on 127.0.0.1:8080 only

### 9. Credentials and job as code (2026-10-22 10:08 UTC, branch `jenkins-casc-automation`)
- `sudo bash scripts/05-install-plugins.sh` (re-run) added `configuration-as-code` and `job-dsl`, for **99 plugins** in total.
- The operator supplied the SWR long-term login and the CCE **internal** kubeconfig (API `10.10.1.103:5443`). They were written to `/etc/jenkins/secrets/{SWR_USER,SWR_PASS,cce-kubeconfig}` as `root:jenkins 0640`. No values are in git.
- `verify.sh` with `SWR_USER`/`SWR_PASS`/`KUBECONFIG_FILE` reported **All checks passed**, including SWR docker login and `kubectl -n sample-app get deployments` as the jenkins user (backend, frontend, orders-backend, all 1/1).
- `sudo bash scripts/09-jenkins-casc.sh`:
  - installed `/etc/jenkins/casc/{credentials,jobs}.yaml`
  - added the drop-in `/etc/systemd/system/jenkins.service.d/casc.conf`
  - restarted Jenkins
- Result: credentials `swr-login` (username resolved) and `cce-kubeconfig` were created, and job `sample-project-sky-47-deploy` was created. No Configuration as Code errors were logged. The admin user `sajeewadev` and the security realm were not touched.
- **Open risk:** this kubeconfig is the console one. `kubectl auth can-i '*' '*' --all-namespaces` answers **yes**, so it has full cluster admin. Replace it with the least-privilege `jenkins-deployer` kubeconfig (`docs/05`) by overwriting `/etc/jenkins/secrets/cce-kubeconfig`, then reload Configuration as Code.
- **Open risk:** authorization is still "Logged-in users can do anything". Switch to matrix security (`docs/03`).

### 10. Remaining (operator, in the browser)
- [x] Unlock Jenkins and create the admin user (`sajeewadev`).
- [ ] Set the Jenkins URL to `https://jenkins.paykoko.pk/`.
- [ ] Set up matrix security and turn sign-up off (`docs/03`).
- [x] Credentials and job: done as code in step 9.
- [ ] Run **Build Now** once on `sample-project-sky-47-deploy` (it only registers the parameters), then do a test deploy with `SERVICES=frontend`.
- [ ] Optional: `scripts/07-harden-ssh.sh`, and the daily backup cron (`docs/07`).
