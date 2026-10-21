#!/usr/bin/env bash
# OPTIONAL: nginx on :80 in front of Jenkins (:JENKINS_PORT). Add TLS later with
# certbot or by putting a sky47 ELB with a certificate in front of the VM.
source "$(dirname "$0")/lib.sh"
require_root
load_env

log "Installing nginx"
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

cat > /etc/nginx/sites-available/jenkins <<EOF
upstream jenkins {
  keepalive 32;
  server 127.0.0.1:${JENKINS_PORT};
}

map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  server_name ${JENKINS_DOMAIN};

  client_max_body_size 100m;
  ignore_invalid_headers off;

  location / {
    proxy_pass         http://jenkins;
    proxy_http_version 1.1;
    proxy_set_header   Host              \$http_host;
    proxy_set_header   X-Real-IP         \$remote_addr;
    proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto \$scheme;
    proxy_set_header   Upgrade           \$http_upgrade;
    proxy_set_header   Connection        \$connection_upgrade;
    proxy_buffering    off;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
  }
}
EOF

ln -sf /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

ok "nginx proxying :80 -> 127.0.0.1:${JENKINS_PORT}. Update Manage Jenkins > System > Jenkins URL."
