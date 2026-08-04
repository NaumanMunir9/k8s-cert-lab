#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "coverage.sh is executable" {
  [ -x "${REPO_ROOT}/bin/coverage.sh" ]
}

@test "coverage.sh lists every CKA v1.35 domain" {
  run "${REPO_ROOT}/bin/coverage.sh"
  [ "$status" -eq 0 ]
  for d in Troubleshooting "Cluster Architecture" "Servicing and Networking" \
           "Workloads and Scheduling" Storage; do
    [[ "$output" == *"$d"* ]]
  done
}

@test "coverage.sh lists every CKS v1.34 domain" {
  run "${REPO_ROOT}/bin/coverage.sh"
  for d in "Cluster Setup" "Cluster Hardening" "System Hardening" \
           "Minimize Microservice Vulnerabilities" "Supply Chain Security" \
           "Monitoring, Logging and Runtime Security"; do
    [[ "$output" == *"$d"* ]]
  done
}

@test "coverage.sh counts the existing troubleshooting scenario" {
  run "${REPO_ROOT}/bin/coverage.sh"
  [[ "$output" =~ Troubleshooting[[:space:]]*\|[[:space:]]*30%[[:space:]]*\|[[:space:]]*[1-9] ]]
}

@test "coverage.sh flags a domain with no scenarios as a gap" {
  run "${REPO_ROOT}/bin/coverage.sh"
  [[ "$output" == *"GAP"* ]]
}
