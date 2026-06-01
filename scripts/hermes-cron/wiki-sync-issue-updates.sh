#!/bin/sh
# Hermes cron: wiki-sync-issue-updates
# Schedule: via systemd timer
# Source: OpenClaw jobs.json migration

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/wiki-sync-issue-updates.log"

{
  echo "=== $(date) ==="
  echo "Running: wiki-sync-issue-updates"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use the redmine-wiki and redmine-issue skills to sync recent Redmine issue updates to relevant wiki pages. Check for issue status changes, new comments, or resolved issues that should be reflected in wiki documentation."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
