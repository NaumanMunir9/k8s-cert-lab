#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "doctor.sh is executable" {
  [ -x "${REPO_ROOT}/bin/doctor.sh" ]
}

@test "doctor.sh exits 0 when host tooling meets the floors" {
  run "${REPO_ROOT}/bin/doctor.sh"
  # Print on failure: without this the only diagnostic is "[ $status -eq 0 ] failed", which
  # says nothing about WHICH floor the host missed.
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "doctor.sh reports the kind version it found against the floor" {
  run "${REPO_ROOT}/bin/doctor.sh"
  [[ "$output" == *"kind: 0.3"* ]]
  [[ "$output" == *">= 0.32.0"* ]]
}

# PATH=/nonexistent does NOT test this: it breaks the `#!/usr/bin/env bash` shebang, so
# doctor.sh never runs and the assertion passes on a 127 exec failure. Build a shim PATH
# holding every command doctor.sh needs EXCEPT kind, so the script really executes and
# really reports kind missing. `mkdir` belongs in the list because common.sh calls it at
# source time. Use `type -P`, not `command -v`: command -v returns the bare name for a
# shell function or alias, which would create a self-referential dangling symlink.
@test "doctor.sh fails when a required tool is absent from PATH" {
  shim="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$shim"
  for c in bash env sed head sort grep dirname mkdir sysctl docker kubectl shellcheck yq jq; do
    p=$(type -P "$c") && ln -sf "$p" "$shim/$c"
  done
  rm -f "$shim/kind"
  run env PATH="$shim" "${REPO_ROOT}/bin/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: not installed"* ]]
}

# jq prints `jq-1.7` — two components, no patch. A three-part-only version pattern found
# nothing here and doctor.sh reported "jq: not installed" on a host that had it.
@test "doctor.sh accepts a two-component version like jq-1.7" {
  run bash -c "
    source '${REPO_ROOT}/lib/common.sh'
    ver() { grep -oE '[0-9]+\\.[0-9]+(\\.[0-9]+)?' <<<\"\$1\" | head -1; }
    v=\$(ver 'jq-1.7')
    [ \"\$v\" = '1.7' ] || { echo \"parsed '\$v', expected 1.7\"; exit 1; }
    require_cmd jq 1.7 \"\$v\"
  "
  echo "$output"
  [ "$status" -eq 0 ]
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
