#!/usr/bin/env bash
# Install plugins from config/plugins.txt with the official plugin manager.
# It reads the version from jenkins.war and picks the latest compatible plugin
# releases plus their dependencies. Re-run any time to update plugins.
source "$(dirname "$0")/lib.sh"
require_root
load_env

PLUGIN_FILE="$REPO_ROOT/config/plugins.txt"
JENKINS_WAR=/usr/share/java/jenkins.war
PM_DIR=/opt/jenkins-plugin-manager

[[ -f $JENKINS_WAR ]] || die "$JENKINS_WAR not found, run 02-install-jenkins.sh first"

version=${PLUGIN_MANAGER_VERSION:-$(curl -fsSL https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest | jq -r .tag_name)}
[[ -n $version && $version != null ]] || die "Could not resolve plugin manager version; set PLUGIN_MANAGER_VERSION"
PM_JAR="$PM_DIR/jenkins-plugin-manager-${version}.jar"

if [[ ! -f $PM_JAR ]]; then
  log "Downloading jenkins-plugin-manager $version"
  install -d "$PM_DIR"
  curl -fsSLo "$PM_JAR" \
    "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${version}/jenkins-plugin-manager-${version}.jar"
fi

log "Stopping Jenkins to install plugins"
systemctl stop jenkins

java -jar "$PM_JAR" \
  --war "$JENKINS_WAR" \
  --plugin-download-directory "$JENKINS_HOME_DIR/plugins" \
  --plugin-file "$PLUGIN_FILE" \
  --verbose

chown -R jenkins:jenkins "$JENKINS_HOME_DIR/plugins"

# Exact versions for disaster recovery: to rebuild an identical server, use this
# file as --plugin-file instead of config/plugins.txt (it is in every backup).
log "Recording installed plugin versions -> $JENKINS_HOME_DIR/INSTALLED_PLUGINS.txt"
for f in "$JENKINS_HOME_DIR"/plugins/*.jpi "$JENKINS_HOME_DIR"/plugins/*.hpi; do
  [[ -f $f ]] || continue
  name=$(basename "${f%.*}")
  ver=$(unzip -p "$f" META-INF/MANIFEST.MF | awk -F': ' '/^Plugin-Version:/ {print $2}' | tr -d '\r')
  echo "$name:$ver"
done | sort > "$JENKINS_HOME_DIR/INSTALLED_PLUGINS.txt"
chown jenkins:jenkins "$JENKINS_HOME_DIR/INSTALLED_PLUGINS.txt"

systemctl start jenkins
wait_for_jenkins
ok "Plugins installed: $(find "$JENKINS_HOME_DIR/plugins" -maxdepth 1 \( -name '*.jpi' -o -name '*.hpi' \) | wc -l) files"
