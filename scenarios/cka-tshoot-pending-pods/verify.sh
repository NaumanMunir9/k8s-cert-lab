#!/usr/bin/env bash
# Asserts the correct end state. Read-only — never mutates.

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR/../../lib
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/guard.sh"
guard_init trio
guard_assert_context

NS=tshoot-pending
failed=0

if ! kc get namespace "$NS" >/dev/null 2>&1; then
  die "namespace ${NS} does not exist — run setup first"
fi

if ! kc -n "$NS" get deployment checkout >/dev/null 2>&1; then
  die "deployment 'checkout' not found in ${NS} — it must not be deleted"
fi

replicas=$(kc -n "$NS" get deployment checkout -o jsonpath='{.spec.replicas}')
if [ "$replicas" -eq 3 ]; then
  log_info "spec.replicas is 3"
else
  log_error "spec.replicas is ${replicas}, expected 3 (the constraint was to keep 3)"
  failed=1
fi

image=$(kc -n "$NS" get deployment checkout -o jsonpath='{.spec.template.spec.containers[0].image}')
if [ "$image" = "registry.k8s.io/pause:3.10" ]; then
  log_info "image unchanged"
else
  log_error "image is '${image}', expected 'registry.k8s.io/pause:3.10' (the constraint was not to change it)"
  failed=1
fi

ready=$(kc -n "$NS" get deployment checkout -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
ready="${ready:-0}"
if [ "$ready" -eq 3 ]; then
  log_info "3/3 replicas Ready"
else
  log_error "only ${ready}/3 replicas Ready"
  log_error "pod states:"
  kc -n "$NS" get pods -o wide >&2 || true
  log_error "why the newest pod is not running:"
  pod=$(kc -n "$NS" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$pod" ] && kc -n "$NS" describe pod "$pod" 2>&1 \
    | sed -n '/^Events:/,$p' | head -20 >&2 || true
  failed=1
fi

[ "$failed" -eq 0 ] || die "VERIFY FAILED"
log_info "VERIFY PASSED"
