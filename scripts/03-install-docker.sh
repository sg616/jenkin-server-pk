#!/usr/bin/env bash
# Docker CE + buildx from Docker's official repo. The pipeline builds the
# multi-stage Dockerfiles, so no JDK/Maven/Node toolchain is needed on the host.
source "$(dirname "$0")/lib.sh"
require_root
load_env

if ! command -v docker >/dev/null; then
  log "Adding Docker apt repository"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
    > /etc/apt/sources.list.d/docker.list

  log "Installing Docker CE"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  log "Docker already installed: $(docker --version)"
fi

systemctl enable --now docker

log "Adding jenkins user to the docker group"
usermod -aG docker jenkins
systemctl restart jenkins
wait_for_jenkins

log "Installing weekly docker cleanup cron (keeps build cache under control)"
cat > /etc/cron.weekly/docker-prune <<'EOF'
#!/bin/sh
docker system prune -af --filter "until=168h" > /var/log/docker-prune.log 2>&1
EOF
chmod +x /etc/cron.weekly/docker-prune

sudo -u jenkins docker info >/dev/null || die "jenkins user cannot talk to Docker"
ok "Docker $(docker --version | awk '{print $3}' | tr -d ,) ready for jenkins user"
