#!/usr/bin/env bash
# Reference solution. Makes verify.sh pass from the state setup.sh produces.

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR/../../lib
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/guard.sh"
guard_init trio
guard_assert_context

NS=tshoot-pending

# Fault 1: nodeSelector disktype=nvme-ultra matches no node.
log_info "fault 1: removing the unsatisfiable nodeSelector"
kc -n "$NS" patch deployment checkout --type=json \
  -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'

# Fault 2: cpu request of 32 exceeds any node's allocatable CPU.
log_info "fault 2: reducing the CPU request to fit a node"
kc -n "$NS" patch deployment checkout --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"50m"}]'

# Fault 3: envFrom references a ConfigMap that does not exist.
log_info "fault 3: creating the missing ConfigMap"
kc -n "$NS" create configmap checkout-config \
  --from-literal=CHECKOUT_MODE=standard \
  --dry-run=client -o yaml | kc -n "$NS" apply -f -

log_info "waiting for rollout"
kc -n "$NS" rollout status deployment/checkout --timeout=180s
