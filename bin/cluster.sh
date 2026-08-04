#!/usr/bin/env bash
# Bring a named kind profile up or down. One cluster at a time.

set -Eeuo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR/../lib
source "${BIN}/../lib/guard.sh"

usage() { die "usage: cluster.sh <up|down|status> <${ALLOWED_PROFILES[*]}>"; }

action="${1:-}"; profile="${2:-}"
[ -n "$action" ] && [ -n "$profile" ] || usage

guard_init "$profile"   # dies on an unknown profile
config="${REPO_ROOT}/profiles/${profile}.yaml"

case "$action" in
  up)
    [ -f "$config" ] || die "profile config not found: ${config}"
    "${BIN}/preflight.sh" "$profile"

    if kind get clusters 2>/dev/null | grep -qx "$profile"; then
      log_info "cluster '${profile}' already exists — reusing it"
      kind export kubeconfig --name "$profile" --kubeconfig "$KUBECONFIG" >/dev/null
    else
      log_info "creating cluster '${profile}' from ${config}"
      kind create cluster --config "$config" --kubeconfig "$KUBECONFIG" --wait 180s
    fi

    guard_assert_context

    if [ "$profile" = "nocni" ]; then
      log_warn "profile 'nocni' has no CNI — nodes stay NotReady and CoreDNS stays Pending until you install one"
      kc get nodes
    else
      log_info "waiting for all nodes to be Ready"
      kc wait --for=condition=Ready nodes --all --timeout=180s
      log_info "waiting for CoreDNS"
      kc -n kube-system rollout status deployment/coredns --timeout=180s
    fi

    kc get nodes -o wide
    log_info "cluster '${profile}' ready — KUBECONFIG=${KUBECONFIG}"
    ;;

  down)
    if kind get clusters 2>/dev/null | grep -qx "$profile"; then
      log_info "deleting cluster '${profile}'"
      kind delete cluster --name "$profile"
    else
      log_warn "cluster '${profile}' is not running"
    fi
    rm -f "$KUBECONFIG"
    log_info "cluster '${profile}' down"
    ;;

  status)
    if kind get clusters 2>/dev/null | grep -qx "$profile"; then
      guard_assert_context
      kc get nodes -o wide
    else
      log_info "cluster '${profile}' is not running"
    fi
    ;;

  *) usage ;;
esac
