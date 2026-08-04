#!/usr/bin/env bash
# Prints curriculum coverage: which exam domains have scenarios, which are gaps.
# Domains and weights are transcribed from the CNCF curriculum PDFs
# (CKA v1.35, CKAD v1.35, CKS v1.34) at https://github.com/cncf/curriculum

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR/../lib
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

CKA_DOMAINS=(
  "Troubleshooting|30%"
  "Cluster Architecture, Installation and Configuration|25%"
  "Servicing and Networking|20%"
  "Workloads and Scheduling|15%"
  "Storage|10%"
)
CKAD_DOMAINS=(
  "Application Environment, Configuration and Security|25%"
  "Application Design and Build|20%"
  "Application Deployment|20%"
  "Services and Networking|20%"
  "Application Observability and Maintenance|15%"
)
CKS_DOMAINS=(
  "Minimize Microservice Vulnerabilities|20%"
  "Supply Chain Security|20%"
  "Monitoring, Logging and Runtime Security|20%"
  "Cluster Setup|15%"
  "Cluster Hardening|15%"
  "System Hardening|10%"
)

count_for() {
  local cert="$1" domain="$2" n=0 d
  for d in "${REPO_ROOT}"/scenarios/*/; do
    [ -f "${d}meta.yaml" ] || continue
    if [ "$(yq -r '.cert' "${d}meta.yaml")" = "$cert" ] \
    && [ "$(yq -r '.domain' "${d}meta.yaml")" = "$domain" ]; then
      n=$((n + 1))
    fi
  done
  printf '%s' "$n"
}

report() {
  local cert="$1" version="$2"; shift 2
  printf '\n## %s %s\n\n' "$cert" "$version"
  printf '| Domain | Weight | Scenarios | Status |\n'
  printf '|---|---|---|---|\n'
  local entry domain weight n status
  for entry in "$@"; do
    domain="${entry%%|*}"; weight="${entry##*|}"
    n="$(count_for "$cert" "$domain")"
    if [ "$n" -eq 0 ]; then status='GAP'; else status='covered'; fi
    printf '| %s | %s | %s | %s |\n' "$domain" "$weight" "$n" "$status"
  done
}

printf '# Curriculum coverage\n'
printf '\nSource: https://github.com/cncf/curriculum\n'
report CKA v1.35 "${CKA_DOMAINS[@]}"
report CKAD v1.35 "${CKAD_DOMAINS[@]}"
report CKS v1.34 "${CKS_DOMAINS[@]}"

total=$(find "${REPO_ROOT}/scenarios" -mindepth 1 -maxdepth 1 -type d | wc -l)
printf '\n**Total scenarios: %s**\n' "$total"
