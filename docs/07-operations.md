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
- The archive contains `secrets/` (`master.key`) and `credentials.xml`, which together decrypt every credential. The script always creates it with mode `0600`. Backups taken while Jenkins is running are fine: tar's "file changed as we read it" warnings are expected.
- **Keep a copy off the VM.** If the VM is lost, the backups on its disk are lost too.
  1. **Encryption key.** Create it on your own machine and import only the **public** key on the VM: `sudo gpg --import jenkins-backup.pub`. Set `BACKUP_GPG_RECIPIENT=<key id or email>`. tar is then streamed straight into gpg, so no unencrypted archive is ever written to disk. Archives are named `*.tar.gz.gpg`. If gpg fails, the partial file is deleted.
  2. **Signing key on the VM.** Without a signature, anyone who can write to the bucket could plant an archive. Restoring it would run their code.
     - Create the key: `sudo gpg --batch --passphrase '' --quick-gen-key 'jenkins-backup-signer' ed25519 sign never`
     - Set `BACKUP_GPG_SIGNER=jenkins-backup-signer`.
     - Set `BACKUP_GPG_SIGNER_FPR=<fingerprint>`. Get it with `sudo gpg --list-keys --with-colons jenkins-backup-signer | awk -F: '/^fpr/ {print $10; exit}'`.
     - Note the fingerprint somewhere outside the VM as well. A rebuilt VM needs it to verify old archives.
     - Import the signer's public key into root's keyring on any VM you restore on.
  3. **Copy only encrypted files** to an OBS bucket, in the same cron job as the backup: `obsutil cp /opt/jenkins-backups/ obs://<bucket>/jenkins/ -r -f -include='*.gpg'`. Turn on bucket versioning, and give write access only to this VM's account.
- `INSTALLED_PLUGINS.txt` (exact plugin versions, written by `05-install-plugins.sh`) and `INSTALLED_VERSION` are inside every backup.
- You can also take a sky47 **EVS disk snapshot** of the VM before each major upgrade.

### Restore
```bash
sudo bash scripts/restore-jenkins.sh /opt/jenkins-backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz[.gpg]
```
A restored `JENKINS_HOME` runs code at startup, so the restore script checks where the archive came from:
- `.gpg` archives need a valid signature from `BACKUP_GPG_SIGNER_FPR`. The decryption private key also has to be in root's keyring during the restore. Remove it again afterwards.
- Unsigned `.tar.gz` archives are only accepted from `BACKUP_DIR` on the same VM.
- `ALLOW_UNSIGNED=1` skips both checks. Use it only for an archive you made and kept under your own control.

The script also tests the archive with `tar -t` **before** stopping Jenkins, so a corrupt file changes nothing.

To rebuild on a new VM **with identical versions**:
1. Run `bootstrap.sh`. It installs the latest LTS.
2. If the backup came from an older LTS, install the same version first: `apt-get install jenkins=<INSTALLED_VERSION>`.
3. Run `restore-jenkins.sh <archive>`.
4. To get exactly the same plugins, run the plugin manager with `--plugin-file /var/lib/jenkins/INSTALLED_PLUGINS.txt`.

### Restore drill (every quarter)
A backup you have never restored is untested.
1. Every quarter, create a temporary VM.
2. Run `bootstrap.sh`, then restore the newest off-VM archive.
3. Log in and check that the job and all three credentials are there.
4. Delete the VM.

## Monitoring (sky47 Cloud Eye)
Create these alarms on the Jenkins VM, and send them to an SMN topic that emails you:
| Metric | Alarm when |
|---|---|
| Disk usage `/` (needs the Cloud Eye agent) | > 80% for 5 min |
| CPU usage | > 90% for 15 min |
| Memory usage (agent) | > 90% for 10 min |
| ECS status | instance stopped or abnormal |
| Website monitoring / HTTP probe on `http://<EIP>:8080/login` (or the HTTPS URL) | not 200 or 403 for 3 checks |

Install the Cloud Eye agent from the console (ECS → instance → **Monitoring → Install Agent**). Without it, disk and memory metrics aren't collected.

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
