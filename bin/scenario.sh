#!/usr/bin/env bash
# Runs one phase of one scenario, with the right cluster up first.

set -Eeuo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR/../lib
source "${BIN}/../lib/guard.sh"

usage() { die "usage: scenario.sh <setup|verify|solve|reset> <slug>"; }

action="${1:-}"; slug="${2:-}"
[ -n "$action" ] && [ -n "$slug" ] || usage

dir="${REPO_ROOT}/scenarios/${slug}"
[ -d "$dir" ] || die "unknown scenario '${slug}' — see: ls scenarios/"
[ -f "${dir}/meta.yaml" ] || die "scenario '${slug}' has no meta.yaml"

profile="$(yq -r '.profile' "${dir}/meta.yaml")"
[ -n "$profile" ] && [ "$profile" != "null" ] || die "scenario '${slug}' declares no profile"

case "$action" in
  setup|verify|solve)
    [ -x "${dir}/${action}.sh" ] || die "${dir}/${action}.sh is missing or not executable"
    "${BIN}/cluster.sh" up "$profile" >/dev/null
    log_info "scenario ${slug}: ${action}"
    exec "${dir}/${action}.sh"
    ;;
  reset)
    log_info "scenario ${slug}: full reset"
    "${BIN}/cluster.sh" down "$profile"
    "${BIN}/cluster.sh" up "$profile" >/dev/null
    exec "${dir}/setup.sh"
    ;;
  *) usage ;;
esac
