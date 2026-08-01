#!/usr/bin/env bash
# Verifies host tooling meets the version floors this repo depends on.

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR/../lib
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

KIND_MIN=0.32.0
HELM_MIN=4.0.0
SHELLCHECK_MIN=0.11.0
YQ_MIN=4.40.0
JQ_MIN=1.7

ver() { sed -nE 's/.*?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' <<<"$1" | head -1; }

failed=0

check() { require_cmd "$1" "$2" "$3" || failed=1; }

check kind       "$KIND_MIN"       "$(ver "$(kind version 2>/dev/null || true)")"
check helm       "$HELM_MIN"       "$(ver "$(helm version --short 2>/dev/null || true)")"
check shellcheck "$SHELLCHECK_MIN" "$(ver "$(shellcheck --version 2>/dev/null | grep -i version: || true)")"
check yq         "$YQ_MIN"         "$(ver "$(yq --version 2>/dev/null || true)")"
check jq         "$JQ_MIN"         "$(ver "$(jq --version 2>/dev/null || true)")"

if command -v kubectl >/dev/null 2>&1; then
  log_info "kubectl: $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion)"
else
  log_error "kubectl: not installed"
  failed=1
fi

if docker info >/dev/null 2>&1; then
  log_info "docker: reachable ($(docker info --format '{{.Driver}}, cgroups v{{.CgroupVersion}}'))"
else
  log_error "docker: daemon not reachable (is it running, and are you in the docker group?)"
  failed=1
fi

instances=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
if [ "$instances" -ge 512 ]; then
  log_info "fs.inotify.max_user_instances: ${instances} (>= 512)"
else
  log_error "fs.inotify.max_user_instances: ${instances} is below 512 — multi-node kind clusters will fail with 'too many open files'"
  failed=1
fi

[ "$failed" -eq 0 ] || die "host tooling check failed — fix the items above before creating a cluster"
log_info "host tooling OK"
