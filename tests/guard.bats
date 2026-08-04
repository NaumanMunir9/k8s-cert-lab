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

# Assert the SPECIFIC message. Every die in guard.sh contains "refusing", so matching
# only that word cannot prove which branch fired — the test would still pass if the
# wrong check rejected the context.
@test "guard_assert_context dies when the context is not a kind context" {
  guard_init solo
  KUBE_CONTEXT="gke_example-corp-prd_northamerica-northeast1_prd"
  run guard_assert_context
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a kind context"* ]]
}

# The `kind-` prefix check alone is security-by-naming-convention: a kubeconfig whose
# context is merely NAMED kind-solo but whose server is a public IP passed the guard and
# reached kubectl. This covers the KUBECONFIG-substitution defence.
@test "guard_assert_context refuses a substituted KUBECONFIG even when the context is named kind-" {
  guard_init solo
  export KUBECONFIG="${BATS_TEST_TMPDIR}/impostor"
  printf 'apiVersion: v1\nkind: Config\nclusters:\n- cluster: {server: "https://34.95.0.1:443"}\n  name: notkind\ncontexts:\n- context: {cluster: notkind, user: u}\n  name: kind-solo\ncurrent-context: kind-solo\nusers:\n- name: u\n  user: {}\n' > "$KUBECONFIG"
  run guard_assert_context
  [ "$status" -ne 0 ]
  [[ "$output" == *"KUBECONFIG is"* ]]
}

# These two use the REAL repo-local kubeconfig path, because guard_assert_context now
# requires KUBECONFIG to equal it — so they skip when a solo cluster is actually up
# rather than disturbing its kubeconfig.
@test "guard_assert_context dies when the kubeconfig file does not exist" {
  guard_init solo
  [ -f "$KUBECONFIG" ] && skip "a solo cluster is up; not disturbing its kubeconfig"
  run guard_assert_context
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "guard_assert_context dies when the active context does not match" {
  guard_init solo
  [ -f "$KUBECONFIG" ] && skip "a solo cluster is up; not disturbing its kubeconfig"
  printf 'apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\n' > "$KUBECONFIG"
  run guard_assert_context
  rm -f "$KUBECONFIG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"active context is"* ]]
}

@test "kc refuses to run when the context is not a kind context" {
  guard_init solo
  KUBE_CONTEXT="gke_example-corp-prd_northamerica-northeast1_prd"
  run kc get nodes
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a kind context"* ]]
}

# kubectl resolves the LAST occurrence of a flag, so a caller appending its own --context
# would silently retarget the command. Verified live: `kubectl --context kind-solo
# --context bogus-prod get nodes` resolves bogus-prod.
@test "kc refuses a caller-supplied target override" {
  guard_init solo
  for flag in --context --kubeconfig --server -s; do
    run kc get nodes "$flag" anything
    [ "$status" -ne 0 ]
    [[ "$output" == *"kc does not accept"* ]]
  done
  run kc get nodes --context=bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"kc does not accept --context"* ]]
}
