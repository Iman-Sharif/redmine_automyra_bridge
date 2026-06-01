# Redmine MCP Reconnect Procedure

This document describes the step-by-step recovery process when the OpenCode-integrated Redmine MCP tool namespace returns **Not connected**.

## 1. Identify the symptom

In OpenCode, if MCP tool calls return `Not connected` or time out, the stdio transport link between OpenCode and the Redmine MCP server is broken.

## 2. Check for stale server processes

Run the orphan-detection script (safe — lists only by default):

```bash
bash /opt/redmica/scripts/kill-stale-mcp-server.sh
```

If orphan `mcp-server-redmine` processes are reported, terminate them:

```bash
bash /opt/redmica/scripts/kill-stale-mcp-server.sh --force
```

> The script checks each process's parent PID and whether its stdin file descriptor is still attached to a pipe/terminal. Processes with closed stdin or parent PID 1 (init) are treated as orphans and are safe to kill.

## 3. Verify the MCP server build

Ensure `dist/index.js` exists and is up to date:

```bash
cd /opt/redmica/redmine-mcp-server-src
npm run build
```

## 4. Run the standalone health check

Confirm the server can start and answer MCP requests independently of OpenCode:

```bash
bash /opt/redmica/scripts/redmine-mcp-health-check.sh
```

Expected output is a JSON blob ending with `"overall": "SUCCESS"`.

## 5. Inspect OpenCode MCP configuration

Open `/root/.config/opencode/opencode.json` and verify the `mcp.redmine` block:

- `type` should be `"local"`.
- `command` should point to an executable that launches the server (e.g. `/usr/local/bin/mcp-server-redmine` or the wrapper script).
- `environment.REDMINE_URL` should be `http://127.0.0.1:4000`.
- `environment.REDMINE_API_KEY` must be present and valid.
- `enabled` must be `true`.

## 6. Restart the Manifest gateway (if applicable)

If you are running a local Manifest gateway (`oa-gpt-nms1`, `oa-kimi-1`, etc.) on `http://localhost:3001`, restart it so that any cached MCP process references are cleared:

```bash
# Example: if Manifest is managed by systemd or a custom launcher
# Replace with your actual restart command
systemctl restart manifest-gateway   # or
pm2 restart manifest                 # or
# stop and start the process manually
```

Wait until the gateway health endpoint responds:

```bash
curl -s http://localhost:3001/v1/models || echo "Manifest not ready"
```

## 7. Reload OpenCode MCP configuration

In OpenCode, trigger an MCP reload. The exact method depends on the OpenCode client:

- **Cline / VS Code extension**: Open the MCP settings panel and click **Refresh** or **Reload Servers**.
- **OpenCode CLI**: Run the MCP sync command if one exists in your plugin (e.g. `oh-my-openagent` may provide a `/reload_mcp` slash command).
- **Restart OpenCode entirely**: Close and reopen the OpenCode chat / extension host to force re-initialization of all MCP transports.

## 8. Verify the reconnect with a real tool call

After reload, ask OpenCode to execute:

```
Call redmine_list_projects and tell me how many projects there are.
```

If the response includes project data, the reconnect succeeded.

If it still fails, repeat steps 2–4 and check OpenCode logs for transport errors (e.g., `SIGPIPE`, `ECONNRESET`, or `TypeError: this._buffer.subarray is not a function`).

## 9. Escalation checklist

If the above steps do not restore connectivity:

1. Capture the health-check JSON output and the OpenCode error message.
2. Check Redmica availability directly: `curl -s http://127.0.0.1:4000/projects.json?limit=1`.
3. Verify the API key is not expired or revoked.
4. Open a task in the project tracker with the collected diagnostics.
