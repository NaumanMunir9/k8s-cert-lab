#!/usr/bin/env bash
# Refuses to start a cluster (or a recording) when the host cannot support it.

set -Eeuo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source-path=SCRIPTDIR/../lib
source "${LIB}/guard.sh"

# Measured 2026-08-04: cached node images 0.9 GiB, a running trio adds ~2 GiB of writable
# layers. 8 GiB is ~2.5x the peak need. Do NOT set this to whatever `df` happens to report
# today — the previous 18 and 16 GiB values were, and each blocked every run once free
# space drifted by 1 GiB.
MIN_DISK_GIB="${LAB_MIN_DISK_GIB:-8}"
OBS_MIB=400

profile="${1:-}"
[ -n "$profile" ] || die "usage: preflight.sh <profile> [--recording]"

recording=0
[ "${2:-}" = "--recording" ] && recording=1
[ "${LAB_RECORDING:-0}" = "1" ] && recording=1

# Measured idle 2026-08-04: trio = 783 MiB (control-plane 541, workers 119 + 123). These
# floors stay above that on purpose — scenario workloads add pods on top of an idle cluster.
case "$profile" in
  solo|hardened|etcdlab) need_mib=1000 ;;
  nocni)                 need_mib=1350 ;;
  trio)                  need_mib=1700 ;;
  *) die "unknown profile '${profile}' (allowed: ${ALLOWED_PROFILES[*]})" ;;
esac
[ "$recording" -eq 1 ] && need_mib=$((need_mib + OBS_MIB))

failed=0

# --- disk ---
avail_gib=$(df --output=avail -BG / | tail -1 | tr -d ' G')
if [ "$avail_gib" -ge "$MIN_DISK_GIB" ]; then
  log_info "disk: ${avail_gib} GiB free on / (>= ${MIN_DISK_GIB} GiB)"
else
  log_error "disk: only ${avail_gib} GiB free on /, need ${MIN_DISK_GIB} GiB — run 'docker system prune -af' or reclaim caches"
  failed=1
fi

# --- memory ---
avail_mib="${LAB_MEM_OVERRIDE_MIB:-}"
if [ -z "$avail_mib" ]; then
  avail_mib=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
  need_check=$need_mib
else
  need_check="$avail_mib"; avail_mib=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
fi
if [ "$avail_mib" -ge "$need_check" ]; then
  log_info "memory: ${avail_mib} MiB available (profile '${profile}' needs ${need_check} MiB)"
else
  log_error "memory: only ${avail_mib} MiB available, profile '${profile}' needs ${need_check} MiB — close the browser or pick a smaller profile"
  failed=1
fi

# --- one cluster at a time ---
running="$(kind get clusters 2>/dev/null | grep -v '^No kind clusters' || true)"
if [ -n "$running" ]; then
  others="$(grep -vx "$profile" <<<"$running" || true)"
  if [ -n "$others" ]; then
    log_error "cluster: '${others//$'\n'/, }' already running — only one cluster at a time; run 'bin/cluster.sh down <name>' first"
    failed=1
  else
    log_info "cluster: '${profile}' already up"
  fi
else
  log_info "cluster: none running"
fi

# --- recording-only checks ---
if [ "$recording" -eq 1 ]; then
  if [ -n "${KUBECONFIG:-}" ] && [[ "$KUBECONFIG" == *"/.kube/config"* ]]; then
    log_error "recording: KUBECONFIG points at ${KUBECONFIG} — a work context must not be active while recording"
    failed=1
  fi
  for secret in "$HOME/.jira.d/config.yml" "$HOME/.aws/credentials" \
                "$HOME/.config/gcloud/application_default_credentials.json"; do
    if [ -e "$secret" ] && [[ "$PWD" == "$HOME"/* ]] && [[ "$PWD" != "$REPO_ROOT"* ]]; then
      log_error "recording: cwd '${PWD}' is outside the lab repo while ${secret} exists — record from ${REPO_ROOT}"
      failed=1
    fi
  done
  if [ -n "${HISTFILE:-}" ]; then
    log_warn "recording: HISTFILE is set (${HISTFILE}) — use bin/record.sh so shell history is not captured"
  fi
  log_info "recording: credential-exposure checks complete"
fi

[ "$failed" -eq 0 ] || die "preflight failed for profile '${profile}'"
log_info "preflight OK for profile '${profile}'"
