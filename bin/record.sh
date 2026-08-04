#!/usr/bin/env bash
# Launches a clean shell safe to record: no history, no work credentials,
# minimal prompt, repo-local kubeconfig.

set -Eeuo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR/../lib
source "${BIN}/../lib/guard.sh"

FOOTAGE_DIR="${LAB_FOOTAGE_DIR:-${HOME}/k8s-lab-footage}"

profile="${1:-}"
[ -n "$profile" ] || die "usage: record.sh <profile> [--check]"
guard_init "$profile"

check_only=0
[ "${2:-}" = "--check" ] && check_only=1

mkdir -p "$FOOTAGE_DIR" 2>/dev/null || die "footage directory ${FOOTAGE_DIR} cannot be created — is the drive mounted?"
[ -w "$FOOTAGE_DIR" ] || die "footage directory ${FOOTAGE_DIR} is not writable"
avail_gib=$(df -BG --output=avail "$FOOTAGE_DIR" | tail -1 | tr -d ' G')
log_info "footage directory: ${FOOTAGE_DIR} (${avail_gib} GiB free)"

LAB_RECORDING=1 "${BIN}/preflight.sh" "$profile" --recording

if [ "$check_only" -eq 1 ]; then
  log_info "checks passed — rerun without --check to enter the recording shell"
  exit 0
fi

log_info "starting recording shell for profile '${profile}'"
log_info "set OBS's recording path to: ${FOOTAGE_DIR}"

cd "$REPO_ROOT"
# shellcheck disable=SC2016
# The single-quoted -c script below is intentional: ${LAB_PROFILE} must
# expand inside the inner bash process, using its own inherited environment
# set by `env -i` above, not the outer shell that is launching it.
env -i \
  HOME="$HOME" \
  USER="$USER" \
  TERM="${TERM:-xterm-256color}" \
  PATH="$PATH" \
  LANG="${LANG:-en_US.UTF-8}" \
  KUBECONFIG="$KUBECONFIG" \
  KUBE_CONTEXT="$KUBE_CONTEXT" \
  LAB_PROFILE="$profile" \
  bash --noprofile --norc -c '
    # A bare `unset HISTFILE` does NOT survive the `exec bash -i` below: an
    # interactive bash started with HISTFILE absent from the environment
    # re-defaults it to ~/.bash_history on its own. Exporting an EMPTY value
    # is what actually suppresses history (confirmed: `history -a` then
    # reports "HISTFILE: parameter null or not set" and writes nothing).
    unset HISTFILE
    HISTFILE=""
    export HISTFILE
    HISTSIZE=0
    HISTFILESIZE=0
    export HISTSIZE HISTFILESIZE
    unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION
    unset GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_CORE_PROJECT
    unset JIRA_API_TOKEN JIRA_URL GITHUB_TOKEN GH_TOKEN
    PS1="\[\033[0;36m\][${LAB_PROFILE}]\[\033[0m\] \W \$ "
    export PS1
    echo
    echo "Recording shell — profile ${LAB_PROFILE}"
    echo "History is off. Work credentials are unset. Type exit when done."
    echo
    exec bash --noprofile --norc -i
  '
