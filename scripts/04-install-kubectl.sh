#!/usr/bin/env bash
# kubectl for deploying to sky47 CCE. Set KUBECTL_VERSION to the cluster's
# version (kubectl supports +/-1 minor version skew).
source "$(dirname "$0")/lib.sh"
require_root
load_env

version=${KUBECTL_VERSION:-$(curl -fsSL https://dl.k8s.io/release/stable.txt)}
arch=$(dpkg --print-architecture)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log "Installing kubectl $version ($arch)"
curl -fsSLo "$tmp/kubectl"        "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"
curl -fsSLo "$tmp/kubectl.sha256" "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl.sha256"
echo "$(cat "$tmp/kubectl.sha256")  $tmp/kubectl" | sha256sum --check --quiet
install -o root -g root -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl

# Pipelines get the kubeconfig from the `cce-kubeconfig` credential; this dir is
# only for manual debugging as the jenkins user.
install -d -o jenkins -g jenkins -m 0700 "$JENKINS_HOME_DIR/.kube"

ok "kubectl $(kubectl version --client -o json | jq -r .clientVersion.gitVersion) installed"
