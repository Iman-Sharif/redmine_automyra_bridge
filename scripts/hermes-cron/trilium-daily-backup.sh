#!/bin/sh
# Hermes cron: trilium-daily-backup (REWRITE)
# Adapted from OpenClaw job — no direct Hermes equivalent
# Schedule: via systemd timer

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/trilium-daily-backup.log"

{
  echo "=== $(date) ==="
  echo "Running: trilium-daily-backup"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Perform a daily backup of the Trilium Notes database. Use the Trilium ETAPI or direct filesystem copy to create a timestamped backup of the Trilium data. Verify the backup completed successfully and report the backup size."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
