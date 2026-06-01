#!/bin/sh
# Hermes cron: daily-automyra-issue-review
# Schedule: via systemd timer
# Source: OpenClaw jobs.json migration

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/daily-automyra-issue-review.log"

{
  echo "=== $(date) ==="
  echo "Running: daily-automyra-issue-review"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use the redmine-issue skill to perform a daily review of all Automyra Redmine issues. Summarize the current issue landscape, highlight any issues needing attention, and report on progress."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
