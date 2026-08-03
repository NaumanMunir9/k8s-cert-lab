#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "preflight.sh is executable" {
  [ -x "${REPO_ROOT}/bin/preflight.sh" ]
}

@test "preflight.sh rejects a missing profile argument" {
  run "${REPO_ROOT}/bin/preflight.sh"
  [ "$status" -ne 0 ]
}

@test "preflight.sh rejects an unknown profile" {
  run "${REPO_ROOT}/bin/preflight.sh" production
  [ "$status" -ne 0 ]
}

@test "preflight.sh passes for solo on a healthy host" {
  run "${REPO_ROOT}/bin/preflight.sh" solo
  [ "$status" -eq 0 ]
}

@test "preflight.sh reports both disk and memory" {
  run "${REPO_ROOT}/bin/preflight.sh" solo
  [[ "$output" == *"disk"* ]]
  [[ "$output" == *"memory"* ]]
}

@test "preflight.sh fails when the disk floor is raised beyond what is available" {
  run env LAB_MIN_DISK_GIB=100000 "${REPO_ROOT}/bin/preflight.sh" solo
  [ "$status" -ne 0 ]
  [[ "$output" == *"disk"* ]]
}

@test "preflight.sh fails when the memory requirement exceeds what is available" {
  run env LAB_MEM_OVERRIDE_MIB=99999999 "${REPO_ROOT}/bin/preflight.sh" solo
  [ "$status" -ne 0 ]
  [[ "$output" == *"memory"* ]]
}

@test "recording mode fails when a work kube context is active in the environment" {
  run env LAB_RECORDING=1 KUBECONFIG="$HOME/.kube/config" "${REPO_ROOT}/bin/preflight.sh" solo --recording
  [ "$status" -ne 0 ]
}
