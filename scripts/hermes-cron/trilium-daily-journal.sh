#!/bin/sh
# Hermes cron: trilium-daily-journal (REWRITE)
# Adapted from OpenClaw job — no direct Hermes equivalent
# Schedule: via systemd timer

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/trilium-daily-journal.log"

{
  echo "=== $(date) ==="
  echo "Running: trilium-daily-journal"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use the Trilium ETAPI to create a daily journal entry in Trilium Notes. Create a new note with today's date, populate it with a standard journal template, and link it to the journal tree structure."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
