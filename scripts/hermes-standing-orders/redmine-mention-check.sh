#!/bin/sh
# Hermes standing-order: Check Redmine for mentions requiring attention
# Replaces: openclaw standing-order redmine-mention-check
# Schedule: Tue 09:00 (via systemd timer)

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"

LOGFILE="/tmp/hermes/standing-orders.log"

{
  echo "=== $(date) ==="
  echo "Running: redmine-mention-check"
  
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [
        {
          "role": "user",
          "content": "Check Redmine for any mentions of me that require attention. Look for issues where I am assigned or mentioned in recent comments. Provide a brief summary of any items needing action."
        }
      ],
      "stream": false
    }'
  
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
