#!/bin/sh
# Hermes cron: redmica-catalogue-weekly-audit
# Schedule: via systemd timer
# Source: OpenClaw jobs.json migration

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/redmica-catalogue-weekly-audit.log"

{
  echo "=== $(date) ==="
  echo "Running: redmica-catalogue-weekly-audit"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use the redmine-wiki and redmine-issue skills to perform a weekly audit of the Redmica project catalogue. Review wiki pages for accuracy, check project metadata, and report any discrepancies or updates needed."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
