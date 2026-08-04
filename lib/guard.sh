#!/usr/bin/env bash
# Context isolation. Source this before any cluster mutation.
#
# This repo's scripts intentionally break Kubernetes clusters. The same
# workstation holds live production GKE contexts. Everything here exists to
# make a wrong-target run impossible rather than unlikely.

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# readonly so a caller cannot widen the allowed set before calling guard_init.
# Without it, `ALLOWED_PROFILES=(production); guard_init production` succeeded. The
# already-readonly check matters because tests source this file more than once, and
# re-declaring a readonly array is a fatal error under `set -e`.
if ! readonly -p 2>/dev/null | grep -q 'declare -ar ALLOWED_PROFILES'; then
  ALLOWED_PROFILES=(solo trio nocni hardened etcdlab)
  readonly -a ALLOWED_PROFILES
fi

guard_init() {
  local profile="${1:-}"
  [ -n "$profile" ] || die "guard_init: profile argument is required"

  local ok=0 p
  for p in "${ALLOWED_PROFILES[@]}"; do
    [ "$p" = "$profile" ] && ok=1 && break
  done
  [ "$ok" -eq 1 ] || die "guard_init: unknown profile '${profile}' (allowed: ${ALLOWED_PROFILES[*]})"

  # Deliberately NOT ~/.kube/config. Never inherit an ambient kubeconfig.
  KUBECONFIG="${WORK_DIR}/kubeconfig-${profile}"
  KUBE_CONTEXT="kind-${profile}"
  KIND_PROFILE="$profile"
  export KUBECONFIG KUBE_CONTEXT KIND_PROFILE
}

guard_assert_context() {
  [ -n "${KUBE_CONTEXT:-}" ] || die "guard_assert_context: guard_init was never called"

  case "$KUBE_CONTEXT" in
    kind-*) ;;
    *) die "refusing to continue: context '${KUBE_CONTEXT}' is not a kind context" ;;
  esac

  # The kind- prefix check above is only a naming convention. Re-derive the expected
  # kubeconfig path from the profile and refuse anything else, so a KUBECONFIG exported
  # after guard_init cannot smuggle in a foreign cluster under a kind- context name.
  [ "${KUBECONFIG}" = "${WORK_DIR}/kubeconfig-${KIND_PROFILE}" ] \
    || die "refusing to continue: KUBECONFIG is ${KUBECONFIG}, expected ${WORK_DIR}/kubeconfig-${KIND_PROFILE}"

  [ -f "${KUBECONFIG}" ] || die "refusing to continue: kubeconfig ${KUBECONFIG} does not exist — is the cluster up?"

  local current
  current="$(kubectl config current-context 2>/dev/null || true)"
  [ "$current" = "$KUBE_CONTEXT" ] \
    || die "refusing to continue: active context is '${current:-<none>}', expected '${KUBE_CONTEXT}'"

  # Path and name are both forgeable: `kind export kubeconfig` MERGES into an existing
  # file, and .work/ is gitignored and never content-checked, so a file at the pinned
  # path can hold a kind-<profile> context pointing anywhere. A kind API server is always
  # published on a host loopback port, so anything else is not a local cluster.
  local server
  server="$(kubectl config view -o "jsonpath={.clusters[?(@.name=='$(kubectl config view -o "jsonpath={.contexts[?(@.name=='${KUBE_CONTEXT}')].context.cluster}")')].cluster.server}" 2>/dev/null || true)"
  case "$server" in
    https://127.0.0.1:*|https://localhost:*|https://0.0.0.0:*|'https://[::1]:'*) ;;
    *) die "refusing to continue: context '${KUBE_CONTEXT}' points at '${server:-<none>}', which is not a local kind API server" ;;
  esac
}

# All cluster access goes through this. Asserts on every single call.
kc() {
  # kubectl lets the LAST occurrence of a flag win, so a caller passing its own
  # --context/--kubeconfig/--server would silently override the pinned target and defeat
  # every assertion below. Refuse rather than append. This runs BEFORE the context
  # assertions on purpose: kc's own arguments are always checkable, while the assertions
  # can exit first for an unrelated reason (no cluster up yet) and mask a bad call.
  local a
  for a in "$@"; do
    case "$a" in
      --context|--context=*|--kubeconfig|--kubeconfig=*|--server|--server=*|-s)
        die "refusing to continue: kc does not accept ${a%%=*} — the target is fixed by guard_init" ;;
    esac
  done
  guard_assert_context
  kubectl --context "$KUBE_CONTEXT" "$@"
}
