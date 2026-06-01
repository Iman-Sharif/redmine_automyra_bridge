#!/bin/sh
# Hermes cron: wiki-accuracy-review
# Schedule: via systemd timer
# Source: OpenClaw jobs.json migration

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/wiki-accuracy-review.log"

{
  echo "=== $(date) ==="
  echo "Running: wiki-accuracy-review"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use the legal-verify and redmine-wiki skills to perform a weekly accuracy review of wiki content. Verify legal references are current, check factual claims, and flag any content needing updates."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
