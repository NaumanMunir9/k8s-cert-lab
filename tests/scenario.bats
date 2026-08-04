#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "scenario.sh is executable" {
  [ -x "${REPO_ROOT}/bin/scenario.sh" ]
}

@test "scenario.sh rejects an unknown slug" {
  run "${REPO_ROOT}/bin/scenario.sh" setup no-such-scenario
  [ "$status" -ne 0 ]
}

@test "scenario.sh rejects an unknown action" {
  run "${REPO_ROOT}/bin/scenario.sh" detonate cka-tshoot-pending-pods
  [ "$status" -ne 0 ]
}

@test "every scenario has all four contract files" {
  for d in "${REPO_ROOT}"/scenarios/*/; do
    [ -f "${d}meta.yaml" ]
    [ -x "${d}setup.sh" ]
    [ -x "${d}verify.sh" ]
    [ -x "${d}solve.sh" ]
    [ -f "${d}README.md" ]
  done
}

@test "every scenario meta.yaml declares the required fields" {
  for d in "${REPO_ROOT}"/scenarios/*/; do
    for field in slug title profile cert curriculum_version domain difficulty attribution; do
      value="$(yq -r ".${field}" "${d}meta.yaml")"
      [ -n "$value" ]
      [ "$value" != "null" ]
    done
  done
}

@test "every scenario slug matches its directory name" {
  for d in "${REPO_ROOT}"/scenarios/*/; do
    [ "$(basename "$d")" = "$(yq -r '.slug' "${d}meta.yaml")" ]
  done
}

@test "every scenario declares an allowed profile" {
  source "${REPO_ROOT}/lib/guard.sh"
  for d in "${REPO_ROOT}"/scenarios/*/; do
    p="$(yq -r '.profile' "${d}meta.yaml")"
    printf '%s\n' "${ALLOWED_PROFILES[@]}" | grep -qx "$p"
  done
}

@test "no scenario script calls bare kubectl instead of kc" {
  for f in "${REPO_ROOT}"/scenarios/*/{setup,verify,solve}.sh; do
    run grep -nE '(^|[^-[:alnum:]_])kubectl ' "$f"
    [ "$status" -ne 0 ]
  done
}

@test "every scenario script sources the guard" {
  for f in "${REPO_ROOT}"/scenarios/*/{setup,verify,solve}.sh; do
    grep -q 'guard.sh' "$f"
    grep -q 'guard_assert_context' "$f"
  done
}

@test "live: setup breaks it, verify fails, solve fixes it, verify passes" {
  [ "${LAB_LIVE:-0}" = "1" ] || skip "set LAB_LIVE=1 to run the live self-test"
  run "${REPO_ROOT}/bin/scenario.sh" setup cka-tshoot-pending-pods
  [ "$status" -eq 0 ]
  run "${REPO_ROOT}/bin/scenario.sh" verify cka-tshoot-pending-pods
  [ "$status" -ne 0 ]
  run "${REPO_ROOT}/bin/scenario.sh" solve cka-tshoot-pending-pods
  [ "$status" -eq 0 ]
  run "${REPO_ROOT}/bin/scenario.sh" verify cka-tshoot-pending-pods
  [ "$status" -eq 0 ]
}
