#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "doctor.sh is executable" {
  [ -x "${REPO_ROOT}/bin/doctor.sh" ]
}

@test "doctor.sh exits 0 when host tooling meets the floors" {
  run "${REPO_ROOT}/bin/doctor.sh"
  [ "$status" -eq 0 ]
}

@test "doctor.sh reports the kind version floor" {
  run "${REPO_ROOT}/bin/doctor.sh"
  [[ "$output" == *"kind"* ]]
}

@test "doctor.sh fails when a required tool is absent from PATH" {
  run env PATH=/nonexistent "${REPO_ROOT}/bin/doctor.sh"
  [ "$status" -ne 0 ]
}

@test "common.sh require_cmd accepts an equal version" {
  source "${REPO_ROOT}/lib/common.sh"
  run require_cmd kind 0.32.0 0.32.0
  [ "$status" -eq 0 ]
}

@test "common.sh require_cmd rejects an older version" {
  source "${REPO_ROOT}/lib/common.sh"
  run require_cmd kind 0.32.0 0.23.0
  [ "$status" -eq 1 ]
}

@test "common.sh require_cmd accepts a newer version" {
  source "${REPO_ROOT}/lib/common.sh"
  run require_cmd kind 0.32.0 0.33.1
  [ "$status" -eq 0 ]
}
