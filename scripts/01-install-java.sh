#!/usr/bin/env bash
# Java runtime for Jenkins. Must be installed BEFORE Jenkins, otherwise the
# service fails with "failed to find a valid Java installation".
source "$(dirname "$0")/lib.sh"
require_root
load_env

log "Installing $JAVA_PACKAGE"
DEBIAN_FRONTEND=noninteractive apt-get install -y fontconfig "$JAVA_PACKAGE"

java_major=$(java -version 2>&1 | awk -F'"' '/version/ {split($2, v, "."); print v[1]}')
[[ $java_major -ge 21 ]] || die "Java $java_major found; current Jenkins LTS needs Java 21 or 25"
java -version 2>&1 | head -1
ok "Java $java_major installed"
