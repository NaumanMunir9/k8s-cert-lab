#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "record.sh is executable" {
  [ -x "${REPO_ROOT}/bin/record.sh" ]
}

@test "record.sh rejects an unknown profile" {
  run "${REPO_ROOT}/bin/record.sh" production --check
  [ "$status" -ne 0 ]
}

@test "record.sh --check reports the footage directory" {
  run env LAB_FOOTAGE_DIR="${BATS_TEST_TMPDIR}/footage" "${REPO_ROOT}/bin/record.sh" solo --check
  [[ "$output" == *"footage"* ]]
}

@test "record.sh fails when the footage directory is not writable" {
  run env LAB_FOOTAGE_DIR=/proc/nope "${REPO_ROOT}/bin/record.sh" solo --check
  [ "$status" -ne 0 ]
}

@test "record.sh disables shell history in the recording environment" {
  grep -q 'unset HISTFILE' "${REPO_ROOT}/bin/record.sh"
  grep -qE 'HISTSIZE=0|HISTFILESIZE=0' "${REPO_ROOT}/bin/record.sh"
}

@test "record.sh scrubs work credentials from the recording environment" {
  for v in AWS_PROFILE AWS_ACCESS_KEY_ID GOOGLE_APPLICATION_CREDENTIALS JIRA_API_TOKEN; do
    grep -q "$v" "${REPO_ROOT}/bin/record.sh"
  done
}

# The two static-grep tests above (history, credentials) would pass even if
# record.sh only *mentioned* the variable names in a comment and never
# actually unset them. Drive the real clean shell non-interactively (stdin,
# not a TTY) and assert on its actual output, so a regression that removes
# the unset/export lines is caught.

@test "record.sh's clean shell reports no credential env vars present" {
  run env LAB_FOOTAGE_DIR="${BATS_TEST_TMPDIR}/footage" bash -c '
    export AWS_PROFILE=leaked-aws-profile
    export JIRA_API_TOKEN=leaked-jira-token
    printf "env | grep -icE \"aws|google|jira|token\" || echo NO_CREDENTIAL_VARS\nexit\n" \
      | "'"${REPO_ROOT}"'/bin/record.sh" solo
  '
  [[ "$output" == *"NO_CREDENTIAL_VARS"* ]]
}

@test "the credential-leak assertion can actually fail (sanity check on the check itself)" {
  # Prove the grep-based assertion is not vacuous: point it at a plain passthrough
  # shell that does NOT scrub anything, with the same credential vars exported.
  # This must find the leaked vars, demonstrating the assertion is capable of failing.
  run bash -c '
    export AWS_PROFILE=leaked-aws-profile
    export JIRA_API_TOKEN=leaked-jira-token
    env | grep -icE "aws|google|jira|token" || echo NO_CREDENTIAL_VARS
  '
  [[ "$output" != *"NO_CREDENTIAL_VARS"* ]]
  [[ "$output" =~ ^[1-9] ]]
}

@test "record.sh's clean shell has HISTFILE unset, not just inherited" {
  run env LAB_FOOTAGE_DIR="${BATS_TEST_TMPDIR}/footage" HISTFILE="${BATS_TEST_TMPDIR}/leaked_history" bash -c '
    printf "echo HISTFILE=[\${HISTFILE:-unset}]\nexit\n" \
      | "'"${REPO_ROOT}"'/bin/record.sh" solo
  '
  [[ "$output" == *"HISTFILE=[unset]"* ]]
}

@test "record.sh's clean shell uses the repo-local kubeconfig, never ~/.kube/config" {
  run env LAB_FOOTAGE_DIR="${BATS_TEST_TMPDIR}/footage" bash -c '
    printf "echo KUBECONFIG=[\$KUBECONFIG]\nexit\n" \
      | "'"${REPO_ROOT}"'/bin/record.sh" solo
  '
  [[ "$output" == *"KUBECONFIG=[${REPO_ROOT}/.work/kubeconfig-solo]"* ]]
  [[ "$output" != *"/.kube/config"* ]]
}
