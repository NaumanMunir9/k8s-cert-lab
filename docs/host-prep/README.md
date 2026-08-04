# Host prep: what `kind` can and cannot do

This repo runs every profile as a `kind` cluster — normal Docker containers
acting as Kubernetes nodes, not real VMs. Some CKS-curriculum security
features assume a real kernel boundary per node that a shared-kernel
container cannot provide. This page records what was **actually observed**
on the `hardened` profile (`kindest/node:v1.34.8`) on this workstation
(Debian-based container, `containerd://2.3.1`, host kernel
`7.0.0-28-generic`) — not the spec's hypotheses.

Reproduce with:

```bash
bin/cluster.sh up hardened
docker exec hardened-control-plane ls /var/lib/kubelet/seccomp 2>&1 || echo "seccomp dir absent"
docker exec hardened-control-plane sh -c 'cat /sys/module/apparmor/parameters/enabled 2>/dev/null || echo "apparmor not visible in node"'
docker exec hardened-control-plane sh -c 'ls /sys/kernel/security/apparmor 2>/dev/null || echo "apparmor securityfs absent"'
docker exec hardened-control-plane sh -c 'command -v runsc || echo "runsc absent"'
bin/cluster.sh down hardened
```

## Capability matrix

| Feature | Works in kind? | Observed evidence | Workaround |
|---|---|---|---|
| Seccomp (`RuntimeDefault` / `Localhost` profiles) | Yes | `/var/lib/kubelet/seccomp` is absent on the node (no custom profile directory pre-seeded), but a pod with `securityContext.seccompProfile.type: RuntimeDefault` scheduled and reached `Running` without error — the container runtime (containerd) enforces the profile using the shared host kernel's seccomp support (`/proc/sys/kernel/seccomp/actions_avail` lists `kill_process kill_thread trap errno user_notif trace log allow`). Custom `Localhost` profiles need a file placed at `/var/lib/kubelet/seccomp/<profile>` — that directory does not exist by default, so the episode must create it (via an `extraMounts` hop, same pattern as `hardened`'s audit/encryption files) if it demos a custom profile. |
| AppArmor | No (from inside the node) | `/sys/module/apparmor/parameters/enabled` reads `Y` — the **host** kernel has AppArmor compiled in and enabled. But `/sys/kernel/security/apparmor` (the securityfs mount AppArmor profiles are loaded through) is absent inside the `hardened-control-plane` container. `kind` nodes do not get their own securityfs mount; profile loading happens on the host, and the node's container namespace cannot see or load into it. A pod annotated with an AppArmor profile cannot have that profile enforced from inside the kind node. | Demo AppArmor on a throwaway cloud VM (or bare-metal/full-VM host) with a real kernel per node, not a kind cluster. Document this explicitly in the AppArmor episode's intro so viewers are not confused when it does not work locally. |
| RuntimeClass / gVisor (`runsc`) | No | `runsc` is absent from the node's `PATH` and no gVisor runtime is registered with containerd. Installing gVisor inside a kind node is unsupported by upstream kind (it expects to configure the *host's* containerd, not a nested one) and not worth the fragility for a teaching lab. | Demo `RuntimeClass` mechanics (the API object, `runtimeClassName` field, scheduling behavior) using the `runc` default runtime to show the plumbing, then explain gVisor's sandboxing model verbally or with slides. For a hands-on gVisor demo, use a throwaway cloud VM with gVisor installed on the host and a real (non-kind) cluster, or GKE Sandbox. |
| Audit logging (`audit-policy-file`, `audit-log-path`) | Yes | Verified live: creating a Secret produces matching lines in `/var/log/kubernetes/audit.log` inside the node. See `tests/profiles-advanced.bats`. | None needed — first-class kubeadm flag, works fully inside kind via the two-hop mount (`extraMounts` + `apiServer.extraVolumes`). |
| Encryption at rest for Secrets (`encryption-provider-config`) | Yes | Verified live: the raw etcd value for a created Secret is prefixed `k8s:enc:aescbc:v1:lab-key-1:` (ciphertext), not plaintext. Reached via `crictl exec <etcd-container-id> etcdctl ...` — `etcdctl` is not on the node's own `PATH`, only inside the etcd static pod's container image. | None needed for the core feature; only the etcdctl access path is different from a bare-metal node. |

## Why this matters for episode planning

- **Seccomp and encryption/audit episodes:** fully demoable on `kind` with this repo's `hardened` profile. No host prep needed beyond what `bin/cluster.sh up hardened` already does.
- **AppArmor and gVisor episodes:** kind's shared host kernel is a hard wall, not a configuration gap — there is no `kind` flag or mount that fixes it. These episodes need either a documented "this part requires a real VM" callout with viewers following along on a cloud VM, or the episode restructured to teach the API surface without full enforcement.
