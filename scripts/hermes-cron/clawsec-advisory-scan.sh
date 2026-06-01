#!/bin/sh
# Hermes cron: clawsec-advisory-scan
# Schedule: via systemd timer
# Source: OpenClaw jobs.json migration

PATH=/usr/local/bin:/usr/bin:/bin
HERMES_API="http://127.0.0.1:18800/v1/chat/completions"
API_KEY="ee3dfab49501de12296f9d4a7a37d4ceb6a633989e1a8d05"
LOGFILE="/tmp/hermes/cron/clawsec-advisory-scan.log"

{
  echo "=== $(date) ==="
  echo "Running: clawsec-advisory-scan"
  curl -s -X POST "$HERMES_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "model": "hermes-agent",
      "messages": [{"role": "user", "content": "Use the clawsec-suite skill to scan for security advisories and vulnerabilities. Check relevant security feeds and databases for new advisories affecting monitored systems. Report any new findings."}],
      "stream": false
    }'
  echo ""
  echo "--- end ---"
} >> "$LOGFILE" 2>&1
