#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "cluster.sh is executable" {
  [ -x "${REPO_ROOT}/bin/cluster.sh" ]
}

@test "cluster.sh rejects an unknown subcommand" {
  run "${REPO_ROOT}/bin/cluster.sh" sideways solo
  [ "$status" -ne 0 ]
}

@test "cluster.sh rejects an unknown profile" {
  run "${REPO_ROOT}/bin/cluster.sh" up production
  [ "$status" -ne 0 ]
}

# `all(. == "...")` is jq syntax and mikefarah yq rejects it as a bad expression, so the
# original form failed on exit status alone and never inspected an image. Assert the
# returned value, not just the exit code: a passing exit with output `false` is a miss.
@test "every profile yaml pins its node image by digest" {
  for f in "${REPO_ROOT}"/profiles/*.yaml; do
    run yq -r '[.nodes[].image | test("@sha256:[0-9a-f]{64}$")] | all' "$f"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "every profile yaml name matches its filename" {
  for f in "${REPO_ROOT}"/profiles/*.yaml; do
    expected="$(basename "$f" .yaml)"
    actual="$(yq -r '.name' "$f")"
    [ "$expected" = "$actual" ]
  done
}

@test "solo declares exactly one node" {
  [ "$(yq -r '.nodes | length' "${REPO_ROOT}/profiles/solo.yaml")" -eq 1 ]
}

@test "trio declares one control-plane and two workers" {
  [ "$(yq -r '[.nodes[] | select(.role=="control-plane")] | length' "${REPO_ROOT}/profiles/trio.yaml")" -eq 1 ]
  [ "$(yq -r '[.nodes[] | select(.role=="worker")] | length' "${REPO_ROOT}/profiles/trio.yaml")" -eq 2 ]
}

@test "live: solo comes up, is Ready, and writes a repo-local kubeconfig" {
  [ "${LAB_LIVE:-0}" = "1" ] || skip "set LAB_LIVE=1 to run live cluster tests"
  run "${REPO_ROOT}/bin/cluster.sh" up solo
  [ "$status" -eq 0 ]
  [ -f "${REPO_ROOT}/.work/kubeconfig-solo" ]
  run env KUBECONFIG="${REPO_ROOT}/.work/kubeconfig-solo" \
      kubectl --context kind-solo get nodes --no-headers
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ready"* ]]
  run "${REPO_ROOT}/bin/cluster.sh" down solo
  [ "$status" -eq 0 ]
  [ ! -f "${REPO_ROOT}/.work/kubeconfig-solo" ]
}
