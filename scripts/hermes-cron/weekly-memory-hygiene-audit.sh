#!/bin/sh
# Hermes cron: weekly-memory-hygiene-audit
# Schedule: via systemd timer
# Source: OpenClaw jobs.json migration
# Safety: this job is audit-only. It must not run memory consolidation or deletion.

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="${HERMES_API:-http://127.0.0.1:18800/v1/chat/completions}"
API_KEY="${HERMES_API_KEY:-}"
LOGFILE="${HERMES_MEMORY_HYGIENE_LOG:-/tmp/hermes/cron/weekly-memory-hygiene-audit.log}"

mkdir -p "$(dirname "$LOGFILE")"

if [ -z "$API_KEY" ]; then
  echo "=== $(date) ===" >> "$LOGFILE" 2>&1
  echo "Skipped: HERMES_API_KEY is not set" >> "$LOGFILE" 2>&1
  echo "--- end ---" >> "$LOGFILE" 2>&1
  exit 0
fi

payload=$(cat <<'JSON'
{"model":"hermes-agent","messages":[{"role":"user","content":"Run a memory hygiene DRY-RUN only. Do not call tools. Do not delete, merge, rewrite, compact, promote, consolidate, or otherwise mutate any memory store. Inspect at most 50 recent memories for obvious noise, secrets, or duplicate text and reply with recommended actions only."}],"stream":false}
JSON
)

{
  echo "=== $(date) ==="
  echo "Running: weekly-memory-hygiene-audit dry-run"
  curl -s -X POST "$HERMES_API"     -H "Content-Type: application/json"     -H "Authorization: Bearer $API_KEY"     -d "$payload"
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
