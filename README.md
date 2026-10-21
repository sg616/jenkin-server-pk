# jenkin-server-pk

This repo holds everything needed to build the **Jenkins server** that builds and deploys the services of
[`sample-project-sky-47-deploy-test`](https://github.com/sg616/sample-project-sky-47-deploy-test)
to **sky47 CCE** (Kubernetes) in region `pk-isb-1`.

- Jenkins: **latest stable LTS** from the official `debian-stable` repo. It runs natively under systemd, on Java 21.
- Host: a sky47 ECS Ubuntu VM in the **same VPC as the CCE cluster**, because the cluster API is private.
- Deploys: started by hand, as a parameterized pipeline. There are no webhooks.

## Architecture
```
        you (browser / SSH)
               │  8080 (or 80 via nginx), admin IP only
               ▼
 ┌────────────────────── sky47 VPC ───────────────────────────────┐
 │  ECS VM: Jenkins LTS + Docker + kubectl                        │
 │    │ 1. git clone sample-project-sky-47-deploy-test (GitHub)   │
 │    │ 2. docker build  backend / orders-backend / frontend      │
 │    │ 3. docker push ─────────► SWR swr.pk-isb-1.sky47.com      │
 │    │                              /pk-beta-repo/sample-*       │
 │    │ 4. kubectl set image ───► CCE API (private :5443)         │
 │    ▼                                │                          │
 │                         namespace sample-app                   │
 │                  backend · orders-backend · frontend ◄── ELB 443
 │                              │                                 │
 │                         RDS MySQL 5.7                          │
 └────────────────────────────────────────────────────────────────┘
```

## Quick start
```bash
# on the new VM (docs/01-vm-provisioning.md)
sudo git clone https://github.com/sg616/jenkin-server-pk.git /opt/jenkin-server-pk
cd /opt/jenkin-server-pk
sudo cp config/jenkins.env.example config/jenkins.env   # edit if needed
sudo bash scripts/bootstrap.sh                          # prints the URL and the unlock password
sudo bash scripts/verify.sh
```
Then work through docs 03 → 05 and create the job by following [`jobs/sample-project-sky-47-deploy.md`](jobs/sample-project-sky-47-deploy.md).

## Setup checklist
- [ ] VM created in the CCE VPC, with an EIP and a locked-down security group: [01](docs/01-vm-provisioning.md)
- [ ] `bootstrap.sh` run, and `verify.sh` green: [02](docs/02-install.md)
- [ ] Wizard done, admin user created, matrix security on, sign-up off: [03](docs/03-initial-config.md)
- [ ] `swr-login` credential added (long-term key): [04](docs/04-credentials.md)
- [ ] `cce-kubeconfig` credential added (internal endpoint): [05](docs/05-kubeconfig-cce.md)
- [ ] Job `sample-project-sky-47-deploy` created, and its first run done: [jobs](jobs/sample-project-sky-47-deploy.md)
- [ ] Test deploy: `SERVICES=frontend`, then `ACTION=rollback`: [06](docs/06-pipeline.md)
- [ ] Daily backup cron enabled: [07](docs/07-operations.md)

## Repo layout
| Path | What |
|---|---|
| `config/jenkins.env.example` | Host and tool settings. Copy it to `config/jenkins.env` (git-ignored). |
| `config/plugins.txt` | Jenkins plugins. Versions are unpinned, so each install gets the latest compatible release. |
| `scripts/bootstrap.sh` | Runs `00`–`05` in order. Safe to run again. |
| `scripts/00…06-*.sh` | Each install step on its own (prereqs, Java, Jenkins, Docker, kubectl, plugins, nginx) |
| `scripts/verify.sh` | Health checks: service, Docker, network, SWR login, CCE access |
| `scripts/backup-jenkins.sh`, `restore-jenkins.sh` | JENKINS_HOME backup and restore |
| `pipelines/sample-project-sky-47/Jenkinsfile` | Build → push → deploy/rollback pipeline |
| `jobs/sample-project-sky-47-deploy.md` | Exact steps to create the job |
| `docs/` | Provisioning, install, config, credentials, kubeconfig, pipeline, operations, troubleshooting |

## Secrets
None are stored here. SWR keys and the kubeconfig live only in the Jenkins credential store. `.gitignore` blocks `*.ppk`, `*.pem`, `kubeconfig*` and `config/jenkins.env`.
