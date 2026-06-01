#!/bin/sh
# Hermes standing-order: Memory hygiene review
# Migrated from: openclaw standing-order memory-hygiene-review
# Schedule: Fri 17:00 (via systemd timer)
# Uses: Hermes memory-audit-and-consolidation skill

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"

LOGFILE="/tmp/hermes/standing-orders.log"

{
  echo "=== $(date) ==="
  echo "Running: memory-hygiene-review"
  
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [
        {
          "role": "user",
          "content": "Run the memory-audit-and-consolidation skill. Review MEMORY.md and USER.md for stale entries, verify facts are current, and consolidate any redundant sections. Report any cleanup actions taken."
        }
      ],
      "stream": false
    }'
  
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
