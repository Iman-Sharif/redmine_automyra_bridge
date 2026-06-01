#!/bin/sh
# Hermes cron: Redmica 12-Hour Summary
# Migrated from: OpenClaw job #3
# Schedule: 08:00 and 20:00 daily (via systemd timer)
# Uses: Hermes redmine-issue skill

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/redmica-12h-summary.log"

{
  echo "=== $(date) ==="
  echo "Running: redmica-12h-summary"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use the redmine-issue skill to generate a 12-hour summary of all Redmine activity. Check for new issues, status changes, comments, and updates. Produce a concise summary report of what happened in the last 12 hours."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
