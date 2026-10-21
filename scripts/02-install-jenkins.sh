#!/usr/bin/env bash
# Install the latest STABLE (LTS) Jenkins from the official debian-stable repo.
# No version pin: every run installs/upgrades to the newest LTS available.
source "$(dirname "$0")/lib.sh"
require_root
load_env

# The repo signing key rotates (2023 -> 2026). If apt reports NO_PUBKEY, check
# https://www.jenkins.io/doc/book/installing/linux/ for the current key file.
JENKINS_KEY_URL=https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
KEYRING=/etc/apt/keyrings/jenkins-keyring.asc

log "Adding Jenkins LTS apt repository"
wget -qO "$KEYRING" "$JENKINS_KEY_URL"
echo "deb [signed-by=$KEYRING] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

log "Installing latest Jenkins LTS"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y jenkins

log "Writing systemd override (port $JENKINS_PORT, JAVA_OPTS)"
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JENKINS_PORT=${JENKINS_PORT}"
Environment="JAVA_OPTS=${JENKINS_JAVA_OPTS}"
TimeoutStartSec=600
EOF

systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins
wait_for_jenkins

version=$(jenkins --version)
echo "$version" > "$JENKINS_HOME_DIR/INSTALLED_VERSION"
chown jenkins:jenkins "$JENKINS_HOME_DIR/INSTALLED_VERSION"
ok "Jenkins $version installed (LTS)"
