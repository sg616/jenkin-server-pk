#!/usr/bin/env bash
# OPTIONAL: SSH hardening for the Jenkins VM. Key-only login and fail2ban.
# Make sure your key login works BEFORE running this, or you will lock yourself out.
#   sudo ./scripts/07-harden-ssh.sh
source "$(dirname "$0")/lib.sh"
require_root
load_env

if [[ ! -s /root/.ssh/authorized_keys ]] && ! compgen -G "/home/*/.ssh/authorized_keys" >/dev/null; then
  die "No authorized_keys found for any user; refusing to disable password login"
fi

log "Writing /etc/ssh/sshd_config.d/10-hardening.conf"
cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
EOF

sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd

log "Installing fail2ban (sshd jail)"
DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
maxretry = 5
bantime  = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

ok "SSH hardened: keys only, root via key only, fail2ban active"
