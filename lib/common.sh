#!/usr/bin/env bash
# Shared helpers. Source this, do not execute it.

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${REPO_ROOT}/.work"
export REPO_ROOT WORK_DIR

mkdir -p "${WORK_DIR}"

log_info()  { printf '\033[0;32m[INFO]\033[0m  %s\n' "$*" >&2; }
log_warn()  { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*" >&2; }
log_error() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# require_cmd <name> <min_version> <actual_version>
# Returns 0 if actual >= min using sort -V, 1 otherwise. Both versions bare (no "v").
require_cmd() {
  local name="$1" min="$2" actual="$3"
  if [ -z "$actual" ]; then
    log_error "${name}: not installed (need >= ${min})"
    return 1
  fi
  if [ "$(printf '%s\n%s\n' "$min" "$actual" | sort -V | head -1)" = "$min" ]; then
    log_info "${name}: ${actual} (>= ${min})"
    return 0
  fi
  log_error "${name}: ${actual} is older than required ${min}"
  return 1
}

# wait_for <timeout_seconds> <description> <command...>
# Polls command every 2s until it exits 0, or dies after timeout.
wait_for() {
  local timeout="$1" desc="$2"; shift 2
  local elapsed=0
  until "$@" >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$timeout" ]; then
      die "timed out after ${timeout}s waiting for: ${desc}"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  log_info "ready: ${desc}"
}
