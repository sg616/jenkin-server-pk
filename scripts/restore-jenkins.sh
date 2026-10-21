#!/usr/bin/env bash
# Restore JENKINS_HOME from a backup-jenkins.sh archive.
#   sudo ./scripts/restore-jenkins.sh /opt/jenkins-backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz[.gpg]
#
# A restored JENKINS_HOME runs code at startup (init scripts, job configs, plugins),
# so the archive must be authentic:
#   *.gpg  must carry a valid signature from BACKUP_GPG_SIGNER_FPR
#   *.tar.gz (unsigned) is only accepted from BACKUP_DIR on this VM
# ALLOW_UNSIGNED=1 overrides both checks; use it only for an archive you trust.
source "$(dirname "$0")/lib.sh"
require_root
load_env

archive=${1:-}
[[ -f $archive ]] || die "Usage: $0 <backup.tar.gz | backup.tar.gz.gpg>"
allow_unsigned=${ALLOW_UNSIGNED:-0}

umask 077
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

if [[ $archive == *.gpg ]]; then
  log "Decrypting $archive (needs the private key in root's gpg keyring)"
  status_file="$workdir/gpg.status"
  gpg --batch --yes --status-file "$status_file" --output "$workdir/home.tar.gz" --decrypt "$archive" \
    || die "gpg could not decrypt $archive"

  expected=$(echo "${BACKUP_GPG_SIGNER_FPR:-}" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  if [[ -n $expected ]]; then
    # VALIDSIG <signing-key-fpr> ... <primary-key-fpr>: accept either fingerprint.
    grep -E "^\[GNUPG:\] VALIDSIG " "$status_file" | grep -qw "$expected" \
      || die "No valid signature from $expected on $archive, refusing to restore"
    ok "Signature verified ($expected)"
  elif [[ $allow_unsigned != 1 ]]; then
    die "BACKUP_GPG_SIGNER_FPR not set, cannot verify who made this archive (set it, or ALLOW_UNSIGNED=1)"
  else
    warn "ALLOW_UNSIGNED=1: restoring without signature verification"
  fi
  archive="$workdir/home.tar.gz"
else
  real=$(realpath "$archive")
  if [[ $real != "$(realpath "$BACKUP_DIR")"/* && $allow_unsigned != 1 ]]; then
    die "Unsigned archive outside $BACKUP_DIR: use a signed .gpg backup, or ALLOW_UNSIGNED=1 if you trust it"
  fi
fi

log "Checking archive integrity"
tar -tzf "$archive" >/dev/null || die "Archive is corrupt, nothing was changed"

log "Stopping Jenkins"
systemctl stop jenkins

safety="$JENKINS_HOME_DIR.before-restore-$(date +%Y%m%d-%H%M%S)"
log "Moving current home aside to $safety"
mv "$JENKINS_HOME_DIR" "$safety"
install -d -o jenkins -g jenkins "$JENKINS_HOME_DIR"

log "Extracting archive"
tar -xzf "$archive" -C "$JENKINS_HOME_DIR"
chown -R jenkins:jenkins "$JENKINS_HOME_DIR"

systemctl start jenkins
wait_for_jenkins
ok "Restored. Old home kept at $safety (delete it once everything checks out)."
