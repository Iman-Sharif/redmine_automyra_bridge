#!/usr/bin/env node
import { spawn } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { createInterface } from 'readline';

const MCP_SERVER_PATH = process.env.MCP_SERVER_PATH || '/opt/redmica/scripts/mcp-server-wrapper.js';
const OPENCODE_CONFIG = '/root/.config/opencode/opencode.json';
const PKG_PATH = '/opt/redmica/redmine-mcp-server-src/package.json';

function mask(str) {
  if (!str || str.length < 8) return '***';
  return str.slice(0, 3) + '***' + str.slice(-3);
}

function getApiKeyAndUrl() {
  let apiKey = process.env.REDMINE_API_KEY;
  let redmineUrl = process.env.REDMINE_URL;

  if (!apiKey || !redmineUrl) {
    if (existsSync(OPENCODE_CONFIG)) {
      try {
        const config = JSON.parse(readFileSync(OPENCODE_CONFIG, 'utf8'));
        const env = config.mcp?.redmine?.environment || {};
        if (!apiKey) apiKey = env.REDMINE_API_KEY;
        if (!redmineUrl) redmineUrl = env.REDMINE_URL;
      } catch (e) {
        console.error(`[hc] Warning: could not parse ${OPENCODE_CONFIG}: ${e.message}`);
      }
    }
  }

  if (!redmineUrl) redmineUrl = 'http://127.0.0.1:4000';
  return { apiKey, redmineUrl };
}

async function promptForApiKey() {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question('[hc] REDMINE_API_KEY not found. Please enter API key: ', (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function main() {
  let { apiKey, redmineUrl } = getApiKeyAndUrl();

  if (!apiKey) {
    apiKey = await promptForApiKey();
  }

  if (!apiKey) {
    console.error('[hc] ERROR: REDMINE_API_KEY is required.');
    process.exit(1);
  }

  let pkgVersion = 'unknown';
  try {
    const pkg = JSON.parse(readFileSync(PKG_PATH, 'utf8'));
    pkgVersion = pkg.version || 'unknown';
  } catch {
    pkgVersion = 'unknown';
  }

  const env = {
    ...process.env,
    REDMINE_URL: redmineUrl,
    REDMINE_API_KEY: apiKey,
    LOG_LEVEL: 'warn',
  };

  if (!existsSync(MCP_SERVER_PATH)) {
    console.error(`[hc] ERROR: MCP server not found at ${MCP_SERVER_PATH}. Run 'npm run build' first.`);
    process.exit(1);
  }

  const child = spawn('node', [MCP_SERVER_PATH], {
    env,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  let requestId = 0;
  const pending = new Map();

  function send(method, params) {
    const id = ++requestId;
    const msg = JSON.stringify({ jsonrpc: '2.0', id, method, params });
    child.stdin.write(msg + '\n');
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`Timeout waiting for response to ${method}`));
      }, 10000);
      pending.set(id, (result) => {
        clearTimeout(timer);
        pending.delete(id);
        resolve(result);
      });
    });
  }

  function sendNotification(method, params) {
    const msg = JSON.stringify({ jsonrpc: '2.0', method, params });
    child.stdin.write(msg + '\n');
  }

  let buffer = '';
  child.stdout.on('data', (data) => {
    buffer += data.toString();
    const lines = buffer.split('\n');
    buffer = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (msg.id !== undefined && pending.has(msg.id)) {
          pending.get(msg.id)(msg);
        }
      } catch {

      }
    }
  });

  child.stderr.on('data', (data) => {
    const text = data.toString().trim();
    if (text) {
      const safe = text.replaceAll(apiKey, mask(apiKey));
      // suppress stderr noise in health-check mode
      if (safe.includes('[ERROR]')) {
        console.error(`[hc] Server: ${safe.split('\n')[0]}`);
      }
    }
  });

  await new Promise((r) => setTimeout(r, 600));

  let initOk = false;
  let toolCount = 0;
  let smokeOk = false;
  let errorMsg = '';

  try {
    const initRes = await send('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'redmine-mcp-health-check', version: '1.0.0' },
    });
    initOk = !initRes.error;
    if (!initOk) {
      throw new Error(`initialize failed: ${JSON.stringify(initRes.error)}`);
    }

    sendNotification('notifications/initialized', {});

    const toolsRes = await send('tools/list', {});
    if (toolsRes.error) {
      throw new Error(`tools/list failed: ${JSON.stringify(toolsRes.error)}`);
    }
    toolCount = toolsRes.result?.tools?.length || 0;

    const smokeRes = await send('tools/call', {
      name: 'redmine_list_projects',
      arguments: { limit: 5 },
    });
    if (smokeRes.error) {
      throw new Error(`smoke call failed: ${JSON.stringify(smokeRes.error)}`);
    }
    const contentArr = smokeRes.result?.content || [];
    const text = contentArr.map((c) => (c.type === 'text' ? c.text : '')).join('');
    smokeOk = text.length > 0 && !text.includes('No projects found') && !text.includes('Error executing');
  } catch (err) {
    errorMsg = err.message;
  } finally {
    child.stdin.end();
    child.kill('SIGTERM');
    await new Promise((r) => setTimeout(r, 400));
    if (!child.killed) child.kill('SIGKILL');
  }

  const diagnostics = {
    timestamp: new Date().toISOString(),
    packageVersion: pkgVersion,
    transport: 'stdio',
    redmineUrl,
    authMethod: apiKey ? 'API_KEY' : 'unknown',
    apiKeyMasked: mask(apiKey),
    toolCount,
    initOk,
    smokeOk,
    overall: initOk && smokeOk ? 'SUCCESS' : 'FAILURE',
    error: errorMsg || undefined,
  };

  console.log(JSON.stringify(diagnostics, null, 2));
  process.exit(initOk && smokeOk ? 0 : 1);
}

main().catch((err) => {
  console.error(`[hc] Unhandled error: ${err.message}`);
  process.exit(1);
});
