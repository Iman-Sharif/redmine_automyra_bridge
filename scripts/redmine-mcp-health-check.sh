#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "[redmine-mcp-health-check] ERROR: node is not installed" >&2
  exit 1
fi

exec node "${SCRIPT_DIR}/redmine-mcp-health-check.js" "$@"
