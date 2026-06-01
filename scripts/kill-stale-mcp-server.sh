#!/usr/bin/env bash
set -euo pipefail

FORCE=false
LIST=false

usage() {
  echo "Usage: $(basename "$0") [--force] [--list]"
  echo "  --force  Kill orphan mcp-server-redmine processes without prompting"
  echo "  --list   List all mcp-server-redmine processes and orphan status (default)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --list) LIST=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [[ "$FORCE" == false && "$LIST" == false ]]; then
  LIST=true
fi

mapfile -t PIDS < <(pgrep -d '\n' -f "mcp-server-redmine|redmine-mcp-server-src/dist/index\.js" || true)

if [[ ${#PIDS[@]} -eq 0 || -z "${PIDS[0]}" ]]; then
  echo "No mcp-server-redmine processes found."
  exit 0
fi

orphans=()

for pid in "${PIDS[@]}"; do
  [[ -z "$pid" ]] && continue
  if [[ ! -d "/proc/$pid" ]]; then
    continue
  fi

  ppid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || echo "1")
  cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "unknown")

  fd0_type=""
  if [[ -L "/proc/$pid/fd/0" ]]; then
    fd0_link=$(readlink "/proc/$pid/fd/0" 2>/dev/null || echo "")
    if [[ "$fd0_link" == pipe:* ]]; then
      fd0_type="pipe"
    elif [[ "$fd0_link" == /dev/pts/* || "$fd0_link" == /dev/tty* ]]; then
      fd0_type="terminal"
    elif [[ "$fd0_link" == /dev/null ]]; then
      fd0_type="null"
    else
      fd0_type="other"
    fi
  else
    fd0_type="closed"
  fi

  is_orphan=false
  if [[ "$ppid" == "1" ]]; then
    is_orphan=true
  elif [[ ! -d "/proc/$ppid" ]]; then
    is_orphan=true
  elif [[ "$fd0_type" == "closed" || "$fd0_type" == "null" ]]; then
    is_orphan=true
  fi

  status="active"
  if [[ "$is_orphan" == true ]]; then
    status="ORPHAN"
    orphans+=("$pid")
  fi

  printf 'PID: %-7s | PPID: %-7s | FD0: %-8s | Status: %-6s | CMD: %s\n' "$pid" "$ppid" "$fd0_type" "$status" "$cmdline"
done

if [[ ${#orphans[@]} -eq 0 ]]; then
  echo "No orphan processes found."
  exit 0
fi

if [[ "$LIST" == true ]]; then
  printf '\nFound %d orphan process(s). Use --force to terminate them.\n' "${#orphans[@]}"
  exit 0
fi

if [[ "$FORCE" == true ]]; then
  printf '\nKilling orphan PIDs: %s\n' "${orphans[*]}"
  for pid in "${orphans[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in "${orphans[@]}"; do
    if [[ -d "/proc/$pid" ]]; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
  echo "Done."
fi
