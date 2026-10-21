#!/usr/bin/env bash
# One-shot setup of a fresh Ubuntu VM into a Jenkins server. Idempotent: safe to re-run
# (re-running also upgrades Jenkins to the newest LTS and plugins to latest compatible).
#   sudo ./scripts/bootstrap.sh
source "$(dirname "$0")/lib.sh"
require_root
load_env

for step in 00-prereqs 01-install-java 02-install-jenkins 03-install-docker 04-install-kubectl 05-install-plugins; do
  log "===== $step ====="
  bash "$SCRIPT_DIR/$step.sh"
done

private_ip=$(hostname -I | awk '{print $1}')
echo
ok "Bootstrap complete: $(cat "$JENKINS_HOME_DIR/INSTALLED_VERSION")"
echo "  UI:              http://<EIP from the sky47 console>:${JENKINS_PORT}  (private: http://${private_ip}:${JENKINS_PORT})"
if [[ -f $JENKINS_HOME_DIR/secrets/initialAdminPassword ]]; then
  echo "  Unlock password: $(cat "$JENKINS_HOME_DIR/secrets/initialAdminPassword")"
fi
echo "  Next:            docs/03-initial-config.md"
