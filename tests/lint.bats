#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "all shell scripts pass shellcheck" {
  run bash -c "cd '${REPO_ROOT}' && find bin lib scenarios -name '*.sh' -print0 | xargs -0 shellcheck -x"
  [ "$status" -eq 0 ]
}

@test "all shell scripts use strict mode" {
  for f in "${REPO_ROOT}"/bin/*.sh "${REPO_ROOT}"/lib/*.sh "${REPO_ROOT}"/scenarios/*/*.sh; do
    grep -q 'set -Eeuo pipefail' "$f" || { echo "missing strict mode: $f"; false; }
  done
}

@test "all shell scripts use the env bash shebang" {
  for f in "${REPO_ROOT}"/bin/*.sh "${REPO_ROOT}"/lib/*.sh "${REPO_ROOT}"/scenarios/*/*.sh; do
    head -1 "$f" | grep -q '^#!/usr/bin/env bash' || { echo "bad shebang: $f"; false; }
  done
}

@test "no script references the user's real kubeconfig in executable code" {
  # Comments may name ~/.kube/config to document the safety decision; only
  # real uses are a defect, so strip comment lines before grepping.
  run bash -c "
    cd '${REPO_ROOT}'
    find bin lib scenarios -name '*.sh' -print0 \
      | xargs -0 grep -vE '^[[:space:]]*#' \
      | grep -nE 'HOME/\.kube|~/\.kube'
  "
  [ "$status" -ne 0 ]
}

# `local x="$(kc ...)"` swallows the guard's failure: the builtin's own exit status masks
# the command substitution's, so `die`'s `exit 1` never stops the caller and it continues
# with an empty string. Declare first, assign on the next line.
@test "no script assigns a command substitution inline with local/declare/export" {
  run bash -c "
    cd '${REPO_ROOT}'
    find bin lib scenarios -name '*.sh' -print0 \
      | xargs -0 grep -nE '^[[:space:]]*(local|declare|export)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=\"?\\\$\\('
  "
  [ "$status" -ne 0 ]
}

@test "no committed file contains a plausible live credential" {
  run bash -c "cd '${REPO_ROOT}' && git ls-files -z | xargs -0 grep -lE 'ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'"
  [ "$status" -ne 0 ]
}
