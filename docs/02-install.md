# 2. Install Jenkins (latest LTS) and the tooling

Every step below runs **on the Jenkins VM**.

```bash
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/sg616/jenkin-server-pk.git /opt/jenkin-server-pk
cd /opt/jenkin-server-pk

sudo cp config/jenkins.env.example config/jenkins.env
sudo nano config/jenkins.env          # TIMEZONE, KUBECTL_VERSION (match the CCE version), heap size

sudo bash scripts/bootstrap.sh
```

## What bootstrap does
| Step | Script | Result |
|---|---|---|
| 0 | `00-prereqs.sh` | Base packages and timezone. Adds swap if RAM < 4 GB. Sets up ufw only if `ENABLE_UFW=true`. |
| 1 | `01-install-java.sh` | OpenJDK 21. Current LTS needs Java 21 or 25 (Java 17 support ended at 2.555.1). |
| 2 | `02-install-jenkins.sh` | Adds the **debian-stable** (LTS) repo and installs the **newest LTS**, with no version pin. Writes a systemd override for the port and JAVA_OPTS. |
| 3 | `03-install-docker.sh` | Installs Docker CE and buildx, and adds `jenkins` to the `docker` group. Adds a weekly prune cron job. |
| 4 | `04-install-kubectl.sh` | Installs kubectl (`KUBECTL_VERSION`, or the latest stable) and verifies its checksum |
| 5 | `05-install-plugins.sh` | Installs `config/plugins.txt` at the latest versions compatible with the installed LTS |

When it finishes, bootstrap prints the UI URL, the **initial admin password** and the installed Jenkins version. The version is also saved in `/var/lib/jenkins/INSTALLED_VERSION`.

You can run any single script again later, for example `sudo bash scripts/05-install-plugins.sh` after you edit `plugins.txt`.

## Check
```bash
sudo bash scripts/verify.sh
jenkins --version
```

## Unlock the setup wizard
1. Open `http://<EIP>:8080`.
2. Paste the password. If you lost it, run `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`.
3. **Customize Jenkins**: choose **Select plugins to install → None → Install**. The plugins are already installed from `plugins.txt`.
4. Continue with [03-initial-config.md](03-initial-config.md).

## Optional: nginx on port 80
```bash
sudo bash scripts/06-nginx-reverse-proxy.sh
```
Then set **Manage Jenkins → System → Jenkins URL** to `http://<EIP>/`. In the security group, open 80 and close 8080.
