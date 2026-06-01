#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/redmica"
LOG_DIR="$APP_DIR/log"
LOG_FILE="$LOG_DIR/automyra_bridge_worker.log"
LOCK_FILE="/run/automyra-bridge-worker.lock"

mkdir -p "$LOG_DIR"

{
  printf '[%s] starting Automyra Bridge queue worker\n' "$(date -Is)"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    printf '[%s] skipped Automyra Bridge queue worker because another run is active\n' "$(date -Is)"
    exit 0
  fi

  cd "$APP_DIR"
  docker compose exec -T redmica ruby bin/rails automyra_bridge:process_queue RAILS_ENV=production
  printf '[%s] finished Automyra Bridge queue worker\n' "$(date -Is)"
} >> "$LOG_FILE" 2>&1
