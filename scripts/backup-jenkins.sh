#!/usr/bin/env bash
# Back up JENKINS_HOME (config, jobs, credentials, plugins) without workspaces
# and caches. Keeps the newest BACKUP_KEEP archives.
#   sudo ./scripts/backup-jenkins.sh
# Cron (daily 02:00):
#   echo "0 2 * * * root $PWD/scripts/backup-jenkins.sh" | sudo tee /etc/cron.d/jenkins-backup
source "$(dirname "$0")/lib.sh"
require_root
load_env

install -d -m 0700 "$BACKUP_DIR"
archive="$BACKUP_DIR/jenkins-home-$(date +%Y%m%d-%H%M%S).tar.gz"

log "Backing up $JENKINS_HOME_DIR -> $archive"
tar -czf "$archive" \
  --exclude='./workspace' \
  --exclude='./caches' \
  --exclude='./.cache' \
  --exclude='./logs' \
  --exclude='./war' \
  -C "$JENKINS_HOME_DIR" .
chmod 600 "$archive"

# The archive contains secrets/ (master.key) + credentials.xml: treat it like a password.
ls -1t "$BACKUP_DIR"/jenkins-home-*.tar.gz | tail -n +"$((BACKUP_KEEP + 1))" | xargs -r rm -f
ok "Backup done: $(du -h "$archive" | cut -f1). Kept newest $BACKUP_KEEP."
