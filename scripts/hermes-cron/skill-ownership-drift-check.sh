#!/bin/sh
# Hermes cron: skill-ownership-drift-check (REWRITE)
# Adapted from OpenClaw job — no direct Hermes equivalent
# Schedule: via systemd timer

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/skill-ownership-drift-check.log"

{
  echo "=== $(date) ==="
  echo "Running: skill-ownership-drift-check"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Review the Hermes skill directory structure at /root/.hermes/skills/ and check for ownership drift. Verify that skill directories are properly organized, no orphaned skills exist, and imported skills from openclaw-imports are still valid. Report any drift or inconsistencies."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
