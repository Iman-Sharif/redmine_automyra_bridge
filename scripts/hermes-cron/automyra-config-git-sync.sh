#!/bin/sh
# Hermes cron: automyra-config-git-sync (REWRITE)
# Adapted from OpenClaw job — no direct Hermes equivalent
# Schedule: via systemd timer

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/automyra-config-git-sync.log"

{
  echo "=== $(date) ==="
  echo "Running: automyra-config-git-sync"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Perform a git sync of the Hermes workspace configuration. Check /opt/redmica and /root/.hermes directories for uncommitted changes, stage and commit any configuration drift, and push if remote is configured. Ensure configuration state is preserved in git."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
