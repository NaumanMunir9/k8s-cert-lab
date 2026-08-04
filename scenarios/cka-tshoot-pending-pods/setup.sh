#!/usr/bin/env bash
# Provisions the broken state. Idempotent.

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR/../../lib
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/guard.sh"
guard_init trio
guard_assert_context

NS=tshoot-pending

log_info "resetting namespace ${NS}"
kc delete namespace "$NS" --ignore-not-found --wait=true >/dev/null
kc create namespace "$NS" >/dev/null

log_info "creating a deployment that cannot schedule"
kc -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  labels: { app: checkout }
spec:
  replicas: 3
  selector:
    matchLabels: { app: checkout }
  template:
    metadata:
      labels: { app: checkout }
    spec:
      nodeSelector:
        disktype: nvme-ultra
      containers:
        - name: app
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "32"
              memory: 128Mi
          envFrom:
            - configMapRef:
                name: checkout-config
YAML

log_info "broken state ready"
cat <<'TASK'

  Namespace tshoot-pending has a Deployment 'checkout' with 3 replicas.
  None of its pods are Running. Make all 3 replicas Running.

  Constraints:
    - Keep replicas at 3.
    - Do not change the image.
    - Do not add nodes to the cluster.

  Check your work with: bin/scenario.sh verify cka-tshoot-pending-pods

TASK
