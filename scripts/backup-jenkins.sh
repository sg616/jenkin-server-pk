#!/usr/bin/env bash
# Back up JENKINS_HOME (config, jobs, credentials, plugins) without workspaces
# and caches. Keeps the newest BACKUP_KEEP archives.
# If BACKUP_GPG_RECIPIENT is set, tar is streamed straight into gpg so no
# plaintext archive ever touches the disk; with BACKUP_GPG_SIGNER it is also
# signed so restore-jenkins.sh can verify where it came from.
#   sudo ./scripts/backup-jenkins.sh
# Cron (daily 02:00):
#   echo "0 2 * * * root $PWD/scripts/backup-jenkins.sh" | sudo tee /etc/cron.d/jenkins-backup
source "$(dirname "$0")/lib.sh"
require_root
load_env

# The archive holds secrets/ (master.key) + credentials.xml: never world-readable.
umask 077
install -d -m 0700 "$BACKUP_DIR"
stamp=$(date +%Y%m%d-%H%M%S)
if [[ -n $BACKUP_GPG_RECIPIENT ]]; then
  archive="$BACKUP_DIR/jenkins-home-$stamp.tar.gz.gpg"
  keep_glob='jenkins-home-*.tar.gz.gpg'
else
  archive="$BACKUP_DIR/jenkins-home-$stamp.tar.gz"
  keep_glob='jenkins-home-*.tar.gz'
fi

# Remove a partial/unfinished archive on any failure.
finished=false
trap '[[ $finished == true ]] || rm -f "$archive"' EXIT

tar_args=(
  -cz
  --warning=no-file-changed --ignore-failed-read
  --exclude='./workspace'
  --exclude='./caches'
  --exclude='./.cache'
  --exclude='./logs'
  --exclude='./war'
  -C "$JENKINS_HOME_DIR"
)

log "Backing up $JENKINS_HOME_DIR -> $archive"
# Jenkins keeps writing while we read; tar exits 1 for "file changed as we read
# it", which is fine for a live backup. Only exit >= 2 is a real failure.
if [[ -n $BACKUP_GPG_RECIPIENT ]]; then
  gpg_args=(--batch --yes --trust-model always --recipient "$BACKUP_GPG_RECIPIENT" --output "$archive")
  if [[ -n $BACKUP_GPG_SIGNER ]]; then
    gpg_args+=(--local-user "$BACKUP_GPG_SIGNER" --sign)
  else
    warn "BACKUP_GPG_SIGNER not set: archive is encrypted but unsigned (restore will need ALLOW_UNSIGNED=1)"
  fi
  set +e
  tar "${tar_args[@]}" -f - . | gpg "${gpg_args[@]}" --encrypt
  status=("${PIPESTATUS[@]}")
  set -e
  [[ ${status[0]} -le 1 ]] || die "tar failed with exit code ${status[0]}"
  [[ ${status[1]} -eq 0 ]] || die "gpg failed with exit code ${status[1]}"
else
  rc=0
  tar "${tar_args[@]}" -f "$archive" . || rc=$?
  [[ $rc -le 1 ]] || die "tar failed with exit code $rc"
fi
finished=true

# shellcheck disable=SC2012
ls -1t "$BACKUP_DIR"/$keep_glob | tail -n +"$((BACKUP_KEEP + 1))" | xargs -r rm -f
ok "Backup done: $archive ($(du -h "$archive" | cut -f1)). Kept newest $BACKUP_KEEP."
