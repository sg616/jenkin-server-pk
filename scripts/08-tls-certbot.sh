#!/usr/bin/env bash
# OPTIONAL: HTTPS for the nginx proxy (06) with a Let's Encrypt certificate.
# Needs JENKINS_DOMAIN (a public DNS A record pointing at this VM's EIP),
# CERTBOT_EMAIL, and inbound 80/443 open in the security group (HTTP-01 + renewals).
#   sudo ./scripts/08-tls-certbot.sh
source "$(dirname "$0")/lib.sh"
require_root
load_env

[[ $JENKINS_DOMAIN != _ ]] || die "Set JENKINS_DOMAIN in config/jenkins.env to the public DNS name"
[[ -n $CERTBOT_EMAIL ]] || die "Set CERTBOT_EMAIL in config/jenkins.env (Let's Encrypt expiry notices)"
[[ -f /etc/nginx/sites-available/jenkins ]] || die "nginx site missing, run 06-nginx-reverse-proxy.sh first"

# Fail early with a clear message instead of a Let's Encrypt validation error.
resolved=$(getent ahostsv4 "$JENKINS_DOMAIN" | awk 'NR == 1 {print $1}')
public_ip=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]' || true)
[[ -n $resolved ]] || die "$JENKINS_DOMAIN does not resolve yet; add an A record for this VM's EIP"
if [[ -n $public_ip && $resolved != "$public_ip" ]]; then
  die "$JENKINS_DOMAIN resolves to $resolved, but this VM's public IP is $public_ip"
fi
ok "$JENKINS_DOMAIN -> $resolved"

log "Installing certbot"
DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx

log "Requesting certificate for $JENKINS_DOMAIN (adds the 443 server block and an HTTP->HTTPS redirect)"
certbot --nginx -d "$JENKINS_DOMAIN" --redirect --agree-tos -m "$CERTBOT_EMAIL" -n
nginx -t
systemctl reload nginx

log "Checking automatic renewal (certbot.timer)"
systemctl is-enabled --quiet certbot.timer || warn "certbot.timer is not enabled"
certbot renew --dry-run

ok "HTTPS ready: https://${JENKINS_DOMAIN}/  Set Manage Jenkins > System > Jenkins URL to it."
