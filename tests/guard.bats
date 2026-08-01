#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "${REPO_ROOT}/lib/guard.sh"
}

@test "guard_init sets a repo-local KUBECONFIG" {
  guard_init solo
  [[ "$KUBECONFIG" == "${REPO_ROOT}/.work/kubeconfig-solo" ]]
}

@test "guard_init never points at the user's real kubeconfig" {
  guard_init solo
  [[ "$KUBECONFIG" != "$HOME/.kube/config" ]]
  [[ "$KUBECONFIG" != *"/.kube/config" ]]
}

@test "guard_init sets a kind- prefixed context" {
  guard_init trio
  [ "$KUBE_CONTEXT" = "kind-trio" ]
}

@test "guard_init rejects an empty profile" {
  run guard_init ""
  [ "$status" -ne 0 ]
}

@test "guard_init rejects an unknown profile" {
  run guard_init production
  [ "$status" -ne 0 ]
}

@test "guard_init accepts every allowed profile" {
  for p in solo trio nocni hardened etcdlab; do
    run guard_init "$p"
    [ "$status" -eq 0 ]
  done
}

@test "guard_assert_context dies when the context is not a kind context" {
  guard_init solo
  KUBE_CONTEXT="gke_example-corp-prd_northamerica-northeast1_prd"
  run guard_assert_context
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
}

@test "guard_assert_context dies when the context does not exist in the kubeconfig" {
  guard_init solo
  export KUBECONFIG="${BATS_TEST_TMPDIR}/empty-kubeconfig"
  printf 'apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\n' > "$KUBECONFIG"
  run guard_assert_context
  [ "$status" -ne 0 ]
}

@test "kc refuses to run when the context is not a kind context" {
  guard_init solo
  KUBE_CONTEXT="gke_example-corp-prd_northamerica-northeast1_prd"
  run kc get nodes
  [ "$status" -ne 0 ]
}
