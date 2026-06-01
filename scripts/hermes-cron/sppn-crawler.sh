#!/bin/sh
# Hermes cron: sppn-crawler (REWRITE)
# Adapted from OpenClaw job — no direct Hermes equivalent
# Schedule: via systemd timer

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/sppn-crawler.log"

{
  echo "=== $(date) ==="
  echo "Running: sppn-crawler"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use web search tools to crawl the Scottish Public Procurement Notice portal for new procurement policy notes. Check for updates since the last scan, and create or update relevant Redmine wiki pages or issues for any new SPPN publications found."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
