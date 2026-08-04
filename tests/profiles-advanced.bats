#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "hardened pins the CKS node image v1.34.8" {
  run yq -r '.nodes[0].image' "${REPO_ROOT}/profiles/hardened.yaml"
  [[ "$output" == *"v1.34.8@sha256:02722c2d"* ]]
}

@test "hardened sets both audit and encryption apiserver flags" {
  patch="$(yq -r '.nodes[0].kubeadmConfigPatches[0]' "${REPO_ROOT}/profiles/hardened.yaml")"
  [[ "$patch" == *"audit-policy-file"* ]]
  [[ "$patch" == *"audit-log-path"* ]]
  [[ "$patch" == *"encryption-provider-config"* ]]
}

# The patch is an embedded YAML string, so substring matching on it cannot tell hop 2 from
# hop 1: every one of these directories ALSO appears in extraArgs. Parse the embedded
# document and read hostPath out of extraVolumes specifically, or the test cannot fail.
@test "hardened completes hop 2: every extraArgs file path has a matching extraVolume" {
  run bash -c "yq -r '.nodes[0].kubeadmConfigPatches[0]' '${REPO_ROOT}/profiles/hardened.yaml' \
    | yq -r '[.apiServer.extraVolumes[].hostPath] | sort | join(\",\")'"
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/kubernetes/audit,/etc/kubernetes/encryption,/var/log/kubernetes" ]
}

@test "hardened completes hop 1: policy and encryption files are mounted into the node" {
  run yq -r '[.nodes[0].extraMounts[].containerPath] | join(",")' "${REPO_ROOT}/profiles/hardened.yaml"
  [[ "$output" == *"audit-policy.yaml"* ]]
  [[ "$output" == *"encryption-config.yaml"* ]]
}

@test "hardened referenced host files exist" {
  [ -f "${REPO_ROOT}/profiles/hardened/audit-policy.yaml" ]
  [ -f "${REPO_ROOT}/profiles/hardened/encryption-config.yaml" ]
}

@test "audit policy is valid yaml of the right kind" {
  [ "$(yq -r '.kind' "${REPO_ROOT}/profiles/hardened/audit-policy.yaml")" = "Policy" ]
  [ "$(yq -r '.rules | length' "${REPO_ROOT}/profiles/hardened/audit-policy.yaml")" -gt 0 ]
}

@test "encryption config is valid yaml of the right kind and covers secrets" {
  f="${REPO_ROOT}/profiles/hardened/encryption-config.yaml"
  [ "$(yq -r '.kind' "$f")" = "EncryptionConfiguration" ]
  [ "$(yq -r '.resources[0].resources[0]' "$f")" = "secrets" ]
}

@test "nocni disables the default CNI and kube-proxy" {
  f="${REPO_ROOT}/profiles/nocni.yaml"
  [ "$(yq -r '.networking.disableDefaultCNI' "$f")" = "true" ]
  [ "$(yq -r '.networking.kubeProxyMode' "$f")" = "none" ]
}

@test "nocni uses Calico's default pod subnet" {
  [ "$(yq -r '.networking.podSubnet' "${REPO_ROOT}/profiles/nocni.yaml")" = "192.168.0.0/16" ]
}

@test "etcdlab mounts a writable snapshot directory" {
  f="${REPO_ROOT}/profiles/etcdlab.yaml"
  [ "$(yq -r '.nodes[0].extraMounts[0].containerPath' "$f")" = "/etcd-backup" ]
  [ "$(yq -r '.nodes[0].extraMounts[0].readOnly' "$f")" = "false" ]
}

@test "live: hardened comes up with audit logging and secret encryption working" {
  [ "${LAB_LIVE:-0}" = "1" ] || skip "set LAB_LIVE=1 to run live cluster tests"
  run "${REPO_ROOT}/bin/cluster.sh" up hardened
  [ "$status" -eq 0 ]

  export KUBECONFIG="${REPO_ROOT}/.work/kubeconfig-hardened"

  # Audit log is being written.
  kubectl --context kind-hardened -n default create secret generic audit-canary \
    --from-literal=k=v
  run docker exec hardened-control-plane test -s /var/log/kubernetes/audit.log
  [ "$status" -eq 0 ]
  run docker exec hardened-control-plane grep -c 'audit-canary' /var/log/kubernetes/audit.log
  [ "$status" -eq 0 ]

  # Secrets are encrypted at rest: the raw etcd value must NOT be plaintext.
  # etcdctl is not on the node's PATH — it lives inside the etcd container image,
  # reached via `crictl exec <container-id>` rather than a plain `docker exec ... sh -c`.
  run docker exec hardened-control-plane sh -c \
    'etcd_id=$(crictl ps -a -q --state Running --name etcd | head -1) && \
     crictl exec "$etcd_id" etcdctl \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key \
      get /registry/secrets/default/audit-canary | head -c 200'
  [ "$status" -eq 0 ]
  [[ "$output" == *"k8s:enc:aescbc:v1:lab-key-1"* ]]

  run "${REPO_ROOT}/bin/cluster.sh" down hardened
  [ "$status" -eq 0 ]
}

@test "live: nocni comes up with nodes NotReady and no CNI" {
  [ "${LAB_LIVE:-0}" = "1" ] || skip "set LAB_LIVE=1 to run live cluster tests"
  run "${REPO_ROOT}/bin/cluster.sh" up nocni
  [ "$status" -eq 0 ]
  export KUBECONFIG="${REPO_ROOT}/.work/kubeconfig-nocni"
  run kubectl --context kind-nocni get pods -n kube-system -l k8s-app=kube-dns --no-headers
  [[ "$output" == *"Pending"* ]]
  run "${REPO_ROOT}/bin/cluster.sh" down nocni
  [ "$status" -eq 0 ]
}
