#!/usr/bin/env bash
# Restore JENKINS_HOME from a backup-jenkins.sh archive.
#   sudo ./scripts/restore-jenkins.sh /opt/jenkins-backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz
source "$(dirname "$0")/lib.sh"
require_root
load_env

archive=${1:-}
[[ -f $archive ]] || die "Usage: $0 <backup.tar.gz>"

log "Stopping Jenkins"
systemctl stop jenkins

safety="$JENKINS_HOME_DIR.before-restore-$(date +%Y%m%d-%H%M%S)"
log "Moving current home aside to $safety"
mv "$JENKINS_HOME_DIR" "$safety"
install -d -o jenkins -g jenkins "$JENKINS_HOME_DIR"

log "Extracting $archive"
tar -xzf "$archive" -C "$JENKINS_HOME_DIR"
chown -R jenkins:jenkins "$JENKINS_HOME_DIR"

systemctl start jenkins
wait_for_jenkins
ok "Restored. Old home kept at $safety (delete it once everything checks out)."
