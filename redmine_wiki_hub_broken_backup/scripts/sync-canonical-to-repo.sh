#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
REGRESSION_SCRIPT="${PLUGIN_DIR}/scripts/regression.sh"

CANONICAL_DIR="/opt/redmica/plugins/redmine_wiki_hub"
REPO_DIR="/root/workspace/repos/redmine_wiki_hub"
OPTIONAL_REFERENCE_DIR="/opt/redmine/plugins/redmine_wiki_hub"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1" >&2; }
fail() { log_error "$1"; exit 1; }
precondition_fail() { log_error "$1"; exit 2; }

show_help() {
  cat <<EOF
Canonical to Repository Sync Script

This script enforces the Redmica-first development model:
  - Canonical source: ${CANONICAL_DIR}
  - Repository target: ${REPO_DIR}

Usage:
  $(basename "$0") [OPTIONS]

Options:
  --also-sync-reference    Also sync to optional /opt/redmine reference copy
  --dry-run                Show what would be synced without making changes
  --verify-only            Run post-sync verification only (no sync)
  --help                   Show this help message

Exit Codes:
  0  - Sync completed and verified successfully
  1  - Regression gate failed or sync verification failed
  2  - Preconditions not met (required directories/files missing)

Examples:
  # Standard gated sync (canonical → repo)
  $(basename "$0")

  # Sync with optional reference copy update
  $(basename "$0") --also-sync-reference

  # Verify current sync state without syncing
  $(basename "$0") --verify-only
EOF
}

verify_preconditions() {
  [[ -d "$CANONICAL_DIR" ]] || precondition_fail "Canonical source directory does not exist: ${CANONICAL_DIR}"
  [[ -d "$REPO_DIR" ]] || precondition_fail "Repository target directory does not exist: ${REPO_DIR}"
  [[ -f "$REGRESSION_SCRIPT" ]] || precondition_fail "Regression script not found: ${REGRESSION_SCRIPT}"
  log_success "Preconditions verified"
}

run_regression_gate() {
  log_info "Running regression gate: ${REGRESSION_SCRIPT} --docker"
  log_info "This ensures the canonical code passes the pinned compatibility matrix"
  if "$REGRESSION_SCRIPT" --docker; then
    log_success "Regression gate passed"
  else
    fail "Regression gate FAILED. Sync blocked. Fix canonical code and re-run."
  fi
}

calculate_exclusions() {
  echo "--exclude=.git"
  echo "--exclude=.github"
  echo "--exclude=.sisyphus"
  echo "--exclude=tmp"
  echo "--exclude=node_modules"
  echo "--exclude=coverage"
  echo "--exclude=.bundle"
  echo "--exclude=vendor/bundle"
}

run_sync() {
  local dry_run="${1:-false}"
  local also_reference="${2:-false}"

  log_info "Syncing canonical → repository"
  log_info "  From: ${CANONICAL_DIR}"
  log_info "  To:   ${REPO_DIR}"

  local rsync_opts="-a --delete"
  [[ "$dry_run" == "true" ]] && rsync_opts="${rsync_opts} --dry-run" && log_warn "DRY RUN MODE - no changes will be made"

  local exclude_args=""
  while IFS= read -r exclusion; do
    exclude_args="${exclude_args} ${exclusion}"
  done < <(calculate_exclusions)

  rsync $rsync_opts $exclude_args "${CANONICAL_DIR}/" "${REPO_DIR}/"

  if [[ "$dry_run" == "true" ]]; then
    log_info "Dry-run complete. Run without --dry-run to apply changes."
  else
    log_success "Canonical → repository sync complete"
  fi

  if [[ "$also_reference" == "true" ]]; then
    if [[ -d "$OPTIONAL_REFERENCE_DIR" ]]; then
      log_info "Syncing to optional reference copy: ${OPTIONAL_REFERENCE_DIR}"
      rsync $rsync_opts $exclude_args "${CANONICAL_DIR}/" "${OPTIONAL_REFERENCE_DIR}/"
      log_success "Reference copy sync complete"
    else
      log_warn "Optional reference directory does not exist: ${OPTIONAL_REFERENCE_DIR}"
      log_warn "Skipping reference copy sync"
    fi
  fi
}

run_verification() {
  log_info "Running post-sync verification"
  log_info "Comparing canonical and repository (exit 0 = clean, exit 1 = drift)"

  local diff_output
  diff_output=$(diff -ruN \
    --exclude=.git --exclude=.github --exclude=.sisyphus \
    --exclude=tmp --exclude=node_modules --exclude=coverage \
    --exclude=.bundle --exclude=vendor/bundle \
    "${CANONICAL_DIR}/" \
    "${REPO_DIR}/" 2>&1) || true

  if [[ -z "$diff_output" ]]; then
    log_success "Verification PASSED: canonical and repository are in sync"
    return 0
  else
    log_error "Verification FAILED: drift detected between canonical and repository"
    echo ""
    echo "Differences found:"
    echo "$diff_output" | head -50
    [[ $(echo "$diff_output" | wc -l) -gt 50 ]] && echo "... (showing first 50 lines, $(echo "$diff_output" | wc -l) total)"
    return 1
  fi
}

main() {
  local also_reference="false"
  local dry_run="false"
  local verify_only="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --also-sync-reference) also_reference="true"; shift ;;
      --dry-run) dry_run="true"; shift ;;
      --verify-only) verify_only="true"; shift ;;
      --help|-h) show_help; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  echo "=========================================="
  echo "Wiki Hub Canonical Sync"
  echo "=========================================="
  echo ""

  if [[ "$verify_only" == "true" ]]; then
    verify_preconditions
    run_verification
    exit $?
  fi

  verify_preconditions
  run_regression_gate

  echo ""
  run_sync "$dry_run" "$also_reference"
  echo ""

  if [[ "$dry_run" == "true" ]]; then
    log_warn "Skipping verification (dry-run mode)"
    exit 0
  fi

  if run_verification; then
    echo ""
    echo "=========================================="
    log_success "Canonical sync completed and verified"
    echo "=========================================="
    exit 0
  else
    echo ""
    echo "=========================================="
    log_error "Canonical sync FAILED verification"
    echo "=========================================="
    exit 1
  fi
}

main "$@"
