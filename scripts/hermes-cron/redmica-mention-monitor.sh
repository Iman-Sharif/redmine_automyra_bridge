#!/bin/sh
# Hermes cron: redmica-mention-monitor (REWRITE)
# Adapted from OpenClaw job — no direct Hermes equivalent
# Schedule: via systemd timer

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/redmica-mention-monitor.log"

{
  echo "=== $(date) ==="
  echo "Running: redmica-mention-monitor"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use Redmine tools to check for any mentions of Automyra or related terms in recent Redmine activity. Search issues, comments, and wiki pages for mentions requiring attention or response. This is the core Automyra mention monitor function."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
