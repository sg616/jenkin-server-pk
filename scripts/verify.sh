#!/usr/bin/env bash
# Health checks for the Jenkins host. Optional checks run when their inputs exist:
#   sudo KUBECONFIG_FILE=/path/kubeconfig.json ./scripts/verify.sh
#   sudo SWR_USER='pk-isb-1_<domain>@<AK>' SWR_PASS='<login-key>' ./scripts/verify.sh
source "$(dirname "$0")/lib.sh"
require_root
load_env

SWR_REGISTRY=${SWR_REGISTRY:-swr.pk-isb-1.sky47.com}
K8S_NAMESPACE=${K8S_NAMESPACE:-sample-app}
failures=0

check() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else warn "FAILED: $name"; failures=$((failures + 1)); fi
}

jenkins_serving() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${JENKINS_PORT}/login")
  [[ $code != 000 && $code != 503 ]]
}

java_21_plus() {
  local major
  major=$(java -version 2>&1 | awk -F'"' '/version/ {split($2, v, "."); print v[1]}')
  [[ $major -ge 21 ]]
}

# Any HTTP answer (even 401) proves network reachability; curl exit 0 with -s and no -f.
reachable() { curl -s -o /dev/null --max-time 10 "$1"; }

swr_login() {
  local cfg rc
  cfg=$(mktemp -d)
  echo "$SWR_PASS" | DOCKER_CONFIG=$cfg docker login -u "$SWR_USER" --password-stdin "$SWR_REGISTRY"
  rc=$?
  rm -rf "$cfg"
  return $rc
}

check "jenkins service active"              systemctl is-active --quiet jenkins
check "jenkins serving on :$JENKINS_PORT"   jenkins_serving
check "java >= 21"                          java_21_plus
check "docker usable by jenkins user"       sudo -u jenkins docker info
check "kubectl installed"                   kubectl version --client
check "internet: Docker Hub (base images)"  reachable https://registry-1.docker.io/v2/
check "internet: GitHub (app repo)"         reachable https://github.com
check "network: SWR $SWR_REGISTRY"          reachable "https://${SWR_REGISTRY}/v2/"

if [[ -n ${KUBECONFIG_FILE:-} ]]; then
  # Namespaced call on purpose: works with the least-privilege ServiceAccount too.
  check "kubectl reaches CCE (deployments in $K8S_NAMESPACE)" \
    sudo -u jenkins kubectl --kubeconfig "$KUBECONFIG_FILE" -n "$K8S_NAMESPACE" get deployments
else
  log "Skip CCE check (set KUBECONFIG_FILE=...)"
fi

if [[ -n ${SWR_USER:-} && -n ${SWR_PASS:-} ]]; then
  check "SWR docker login" swr_login
else
  log "Skip SWR login check (set SWR_USER / SWR_PASS)"
fi

if [[ -f $JENKINS_HOME_DIR/INSTALLED_VERSION ]]; then
  log "Jenkins version: $(cat "$JENKINS_HOME_DIR/INSTALLED_VERSION")"
fi
[[ $failures -eq 0 ]] || die "$failures check(s) failed, see docs/08-troubleshooting.md"
ok "All checks passed"
