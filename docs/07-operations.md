# 7. Operations

## Upgrade Jenkins to the newest LTS
Back up first, then upgrade:
```bash
cd /opt/jenkin-server-pk && sudo git pull
sudo bash scripts/backup-jenkins.sh
sudo apt-get update
sudo apt-get install --only-upgrade jenkins        # newest version in debian-stable (LTS)
sudo bash scripts/05-install-plugins.sh            # plugins -> latest compatible with that LTS
jenkins --version | sudo tee /var/lib/jenkins/INSTALLED_VERSION
```
Re-running `sudo bash scripts/bootstrap.sh` does the same thing, because every step can safely run twice.

- Before upgrading, read https://www.jenkins.io/changelog-stable/ and https://www.jenkins.io/doc/upgrade-guide/. Watch for Java requirement changes: current LTS needs Java 21 or 25.
- To freeze the version (for example during a release week), run `sudo apt-mark hold jenkins`. Release it again with `sudo apt-mark unhold jenkins`.
- If a plugin update breaks a job, pin that plugin in `plugins.txt` (`name:version`), run `05-install-plugins.sh` again, and commit.

### Signing key rotation
Jenkins changes the apt repo's signing key from time to time (2023 → 2026). If `apt-get update` shows `NO_PUBKEY`:
1. Check https://www.jenkins.io/doc/book/installing/linux/ for the current key file.
2. Update `JENKINS_KEY_URL` in `scripts/02-install-jenkins.sh`.
3. Run that script again.

## Backups
```bash
sudo bash scripts/backup-jenkins.sh                       # -> /opt/jenkins-backups/jenkins-home-*.tar.gz
echo "0 2 * * * root /opt/jenkin-server-pk/scripts/backup-jenkins.sh" | sudo tee /etc/cron.d/jenkins-backup
```
- The archive contains `secrets/` and `credentials.xml`. Treat it as a secret: `chmod 600`, and store any off-VM copy encrypted (for example in an OBS bucket with server-side encryption).
- You can also take a sky47 **EVS disk snapshot** of the VM before each major upgrade.

### Restore
```bash
sudo bash scripts/restore-jenkins.sh /opt/jenkins-backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz
```
To rebuild on a new VM:
1. Run `bootstrap.sh`.
2. Copy the archive to the new VM.
3. Run `restore-jenkins.sh`.

## Logs and status
```bash
systemctl status jenkins
journalctl -u jenkins -f              # service log
ls /var/lib/jenkins/jobs/sample-project-sky-47-deploy/builds/   # build logs
```

## Disk
- `/etc/cron.weekly/docker-prune` removes images and build cache older than 7 days.
- The pipeline runs `docker image prune -f` and `cleanWs()` after every build.
- Builds are rotated: the job keeps the last 20.
- To check usage: `df -h /`, `docker system df`, `sudo du -sh /var/lib/jenkins/*`.

## Restart safely
**Manage Jenkins → Prepare for Shutdown** lets running builds finish. Then run `sudo systemctl restart jenkins`.
