#!/usr/bin/env bash
# Shared helpers sourced by every script in scripts/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JENKINS_HOME_DIR=/var/lib/jenkins

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
}

require_ubuntu() {
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == ubuntu ]] || warn "Tested on Ubuntu 22.04/24.04, detected: ${PRETTY_NAME:-unknown}"
}

load_env() {
  local env_file="$REPO_ROOT/config/jenkins.env"
  if [[ -f $env_file ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  else
    warn "config/jenkins.env not found, using defaults (cp config/jenkins.env.example config/jenkins.env)"
  fi
  : "${TIMEZONE:=UTC}"
  : "${SWAP_SIZE_GB:=4}"
  : "${ENABLE_UFW:=false}"
  : "${ADMIN_CIDR:=0.0.0.0/0}"
  : "${JENKINS_PORT:=8080}"
  : "${JENKINS_JAVA_OPTS:=-Djava.awt.headless=true -Xms512m -Xmx2g}"
  : "${JAVA_PACKAGE:=openjdk-21-jre}"
  : "${KUBECTL_VERSION:=}"
  : "${PLUGIN_MANAGER_VERSION:=}"
  : "${JENKINS_DOMAIN:=_}"
  : "${BACKUP_DIR:=/opt/jenkins-backups}"
  : "${BACKUP_KEEP:=7}"
  : "${BACKUP_GPG_RECIPIENT:=}"
  : "${BACKUP_GPG_SIGNER:=}"
  : "${BACKUP_GPG_SIGNER_FPR:=}"
}

wait_for_jenkins() {
  # 503 = "Jenkins is getting ready"; 000 = not listening yet. Anything else
  # (200, or 403 while the setup wizard is locked) means it is serving.
  local url="http://127.0.0.1:${JENKINS_PORT}/login" code _
  log "Waiting for Jenkins on $url ..."
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [[ $code != 000 && $code != 503 ]]; then ok "Jenkins is up (HTTP $code)"; return 0; fi
    sleep 5
  done
  die "Jenkins did not come up within 5 minutes (journalctl -u jenkins -n 100)"
}
