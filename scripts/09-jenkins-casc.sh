#!/usr/bin/env bash
# Credentials and the pipeline job as code: installs config/casc/*.yaml for the
# Configuration as Code plugin and points Jenkins at it. Secret values are never
# in git; JCasC reads them from root:jenkins files in SECRETS_DIR at startup.
# Needs the configuration-as-code and job-dsl plugins (05-install-plugins.sh).
#   sudo ./scripts/09-jenkins-casc.sh
# Rotate a secret: replace its file, then Manage Jenkins > Configuration as Code > Reload.
source "$(dirname "$0")/lib.sh"
require_root
load_env

CASC_DIR=/etc/jenkins/casc
SECRETS_DIR=/etc/jenkins/secrets
JOB=sample-project-sky-47-deploy

for p in configuration-as-code job-dsl; do
  compgen -G "$JENKINS_HOME_DIR/plugins/$p.[jh]pi" >/dev/null \
    || die "Plugin $p missing: add it to config/plugins.txt and run 05-install-plugins.sh"
done

install -d -m 0750 -o root -g jenkins "$SECRETS_DIR"
missing=()
for s in SWR_USER SWR_PASS cce-kubeconfig; do
  [[ -s $SECRETS_DIR/$s ]] || missing+=("$s")
done
if (( ${#missing[@]} )); then
  die "Missing secret file(s) in $SECRETS_DIR: ${missing[*]}
  Create them (values never go to git or shell history):
    sudo bash -c 'read -rp \"SWR user (pk-isb-1_<domain>@<AK>): \" v; printf %s \"\$v\" > $SECRETS_DIR/SWR_USER'
    sudo bash -c 'read -rsp \"SWR login key: \" v; printf %s \"\$v\" > $SECRETS_DIR/SWR_PASS'
    sudo install -m 0640 -o root -g jenkins /path/to/kubeconfig.json $SECRETS_DIR/cce-kubeconfig"
fi
chown root:jenkins "$SECRETS_DIR"/*
chmod 0640 "$SECRETS_DIR"/*

log "Installing config/casc/*.yaml -> $CASC_DIR"
install -d -m 0750 -o root -g jenkins "$CASC_DIR"
rm -f "$CASC_DIR"/*.yaml
install -m 0640 -o root -g jenkins "$REPO_ROOT"/config/casc/*.yaml "$CASC_DIR"/

# Own drop-in, so re-running 02-install-jenkins.sh (which rewrites override.conf) keeps it.
log "Writing systemd drop-in casc.conf"
cat > /etc/systemd/system/jenkins.service.d/casc.conf <<EOF
[Service]
Environment="CASC_JENKINS_CONFIG=${CASC_DIR}"
Environment="SECRETS=${SECRETS_DIR}"
EOF
systemctl daemon-reload

since=$(date '+%Y-%m-%d %H:%M:%S')
systemctl restart jenkins
wait_for_jenkins

# Jenkins answers HTTP before JCasC/Job DSL have finished; give them a moment.
for _ in $(seq 1 24); do
  [[ -f $JENKINS_HOME_DIR/jobs/$JOB/config.xml ]] && break
  sleep 5
done
if journalctl -u jenkins --since "$since" --no-pager | grep -qE 'ConfiguratorException|Configuration as Code.*(failed|error)'; then
  die "Configuration as Code reported errors: journalctl -u jenkins --since '$since' | grep -i -A5 casc"
fi
[[ -f $JENKINS_HOME_DIR/jobs/$JOB/config.xml ]] || die "Job $JOB was not created (journalctl -u jenkins --since '$since')"
for id in swr-login cce-kubeconfig; do
  grep -q "<id>$id</id>" "$JENKINS_HOME_DIR/credentials.xml" || die "Credential $id not found in credentials.xml"
done
ok "Credentials swr-login, cce-kubeconfig and job $JOB are managed as code"
