#!/usr/bin/env bash
# Back up JENKINS_HOME (config, jobs, credentials, plugins) without workspaces
# and caches. Keeps the newest BACKUP_KEEP archives. If BACKUP_GPG_RECIPIENT is
# set, the archive is encrypted (.tar.gz.gpg) so it can be copied off the VM.
#   sudo ./scripts/backup-jenkins.sh
# Cron (daily 02:00):
#   echo "0 2 * * * root $PWD/scripts/backup-jenkins.sh" | sudo tee /etc/cron.d/jenkins-backup
source "$(dirname "$0")/lib.sh"
require_root
load_env

# The archive holds secrets/ (master.key) + credentials.xml: never world-readable.
umask 077
install -d -m 0700 "$BACKUP_DIR"
archive="$BACKUP_DIR/jenkins-home-$(date +%Y%m%d-%H%M%S).tar.gz"

log "Backing up $JENKINS_HOME_DIR -> $archive"
# Jenkins keeps writing while we read; tar exits 1 for "file changed as we read
# it", which is fine for a live backup. Only exit >= 2 is a real failure.
rc=0
tar -czf "$archive" \
  --warning=no-file-changed --ignore-failed-read \
  --exclude='./workspace' \
  --exclude='./caches' \
  --exclude='./.cache' \
  --exclude='./logs' \
  --exclude='./war' \
  -C "$JENKINS_HOME_DIR" . || rc=$?
[[ $rc -le 1 ]] || { rm -f "$archive"; die "tar failed with exit code $rc"; }

if [[ -n $BACKUP_GPG_RECIPIENT ]]; then
  log "Encrypting for $BACKUP_GPG_RECIPIENT"
  gpg --batch --yes --trust-model always --recipient "$BACKUP_GPG_RECIPIENT" \
    --output "$archive.gpg" --encrypt "$archive"
  rm -f "$archive"
  archive="$archive.gpg"
fi

ls -1t "$BACKUP_DIR"/jenkins-home-*.tar.gz* | tail -n +"$((BACKUP_KEEP + 1))" | xargs -r rm -f
ok "Backup done: $archive ($(du -h "$archive" | cut -f1)). Kept newest $BACKUP_KEEP."
