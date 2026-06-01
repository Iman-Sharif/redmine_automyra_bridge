#!/bin/sh
# Hermes cron: memory-dreaming-promotion
# Schedule: via systemd timer
# Source: OpenClaw jobs.json migration

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/memory-dreaming-promotion.log"

{
  echo "=== $(date) ==="
  echo "Running: memory-dreaming-promotion"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Run the memory-audit-and-consolidation skill. Perform memory dreaming and short-term promotion: review recent interactions, identify valuable insights worth promoting to long-term memory, and consolidate redundant entries."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
