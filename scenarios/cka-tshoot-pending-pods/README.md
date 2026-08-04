# CKA — A Deployment's pods never leave Pending

| | |
|---|---|
| **Exam** | CKA v1.35 |
| **Domain** | Troubleshooting (30%) |
| **Profile** | `trio` (1 control-plane + 2 workers) |
| **Time budget** | 8 minutes |

## Task

Namespace `tshoot-pending` has a Deployment `checkout` with 3 replicas. None of its
pods are Running. Make all 3 replicas Running.

Constraints: keep `replicas: 3`, do not change the image, do not add nodes.

## Run it

```bash
bin/cluster.sh  up     trio
bin/scenario.sh setup  cka-tshoot-pending-pods
bin/scenario.sh verify cka-tshoot-pending-pods   # fails until you fix it
```

Then point your shell at this cluster, and only this cluster, before running any
`kubectl` command below:

```bash
export KUBECONFIG="$PWD/.work/kubeconfig-trio"
kubectl config current-context   # must print: kind-trio
```

Every `kubectl` command in this walkthrough assumes that export. Without it `kubectl`
uses whatever context your shell already has — which on a work machine may be a real
production cluster.

## Walkthrough

There are **three independent faults**. Fixing one is not enough, which is the point —
`kubectl describe` reports whichever blocks scheduling first, so you must re-check after
each fix rather than assuming you are done.

### Step 1 — see the symptom

```bash
kubectl -n tshoot-pending get pods
```

All pods show `Pending`. `Pending` means the scheduler could not place the pod on any
node; the container image was never pulled and the kubelet was never involved.

### Step 2 — ask the scheduler why

```bash
kubectl -n tshoot-pending describe pod -l app=checkout | sed -n '/^Events:/,$p'
```

The `FailedScheduling` event names the predicates that rejected each node. Expect a
message about node affinity/selector mismatch and about insufficient CPU.

### Step 3 — fault 1, an unsatisfiable nodeSelector

```bash
kubectl -n tshoot-pending get deployment checkout \
  -o jsonpath='{.spec.template.spec.nodeSelector}'
kubectl get nodes --show-labels | tr ',' '\n' | grep disktype || echo "no node has a disktype label"
```

The Deployment requires `disktype=nvme-ultra`. No node carries that label, so no node is
a candidate. Remove the selector:

```bash
kubectl -n tshoot-pending patch deployment checkout --type=json \
  -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
```

Labelling a node would also work, but the task forbids adding nodes and the selector is
the artificial constraint here.

### Step 4 — fault 2, a CPU request no node can satisfy

```bash
kubectl -n tshoot-pending get deployment checkout \
  -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'
kubectl get nodes -o custom-columns='NODE:.metadata.name,CPU:.status.allocatable.cpu'
```

The pod requests `cpu: "32"`. Each kind node advertises the host's CPU count (8 here), and
the scheduler compares the request against **allocatable**, not against idle usage. 32 > 8,
so every node is rejected. Reduce it:

```bash
kubectl -n tshoot-pending patch deployment checkout --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"50m"}]'
```

### Step 5 — fault 3, a missing ConfigMap

Pods now schedule but do not become Ready:

```bash
kubectl -n tshoot-pending get pods
kubectl -n tshoot-pending describe pod -l app=checkout | grep -A3 'State:'
```

The status is `CreateContainerConfigError`. The pod spec has an `envFrom.configMapRef`
naming `checkout-config`, which does not exist. `envFrom` is a hard dependency — the
kubelet cannot build the container's environment, so it will not start the container.
Note the failure moved from the scheduler to the kubelet, which is why the pod is now
assigned to a node but still not Ready.

```bash
kubectl -n tshoot-pending create configmap checkout-config \
  --from-literal=CHECKOUT_MODE=standard
kubectl -n tshoot-pending rollout status deployment/checkout
```

### Step 6 — prove it

```bash
bin/scenario.sh verify cka-tshoot-pending-pods
```

Expected: `VERIFY PASSED`.

## What this tests

`Pending` versus `CreateContainerConfigError` tells you which component rejected the pod.
Pending is the scheduler: predicates such as `nodeSelector`, node affinity, taints, and
resource requests against allocatable. `CreateContainerConfigError` is the kubelet:
missing ConfigMaps, missing Secrets, bad volume references. Reading the phase first tells
you which half of the system to investigate, before you read a single event.

## References

- CKA v1.35 curriculum: <https://github.com/cncf/curriculum>
- [Kubernetes: Pod lifecycle / phases](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Kubernetes: Assigning pods to nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Kubernetes: Resource management for pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
