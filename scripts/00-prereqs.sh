#!/usr/bin/env bash
# Base OS packages, timezone, swap and (optional) ufw.
source "$(dirname "$0")/lib.sh"
require_root
require_ubuntu
load_env

log "Updating apt and installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl wget gnupg git jq unzip fontconfig apt-transport-https
install -m 0755 -d /etc/apt/keyrings

log "Setting timezone to $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if [[ $mem_gb -lt 4 ]] && ! swapon --show | grep -q .; then
  log "RAM is ${mem_gb} GB and no swap: creating ${SWAP_SIZE_GB} GB /swapfile"
  fallocate -l "${SWAP_SIZE_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
  log "Swap not needed (RAM ${mem_gb} GB or swap already present)"
fi

if [[ $ENABLE_UFW == true ]]; then
  log "Configuring ufw: SSH, $JENKINS_PORT, 80 and 443 from $ADMIN_CIDR only"
  apt-get install -y ufw
  for port in 22 "$JENKINS_PORT" 80 443; do
    ufw allow from "$ADMIN_CIDR" to any port "$port" proto tcp
  done
  ufw --force enable
else
  log "ufw left untouched (ENABLE_UFW=false). The sky47 security group controls access."
fi

ok "Prerequisites done"
