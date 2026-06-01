#!/usr/bin/env node
import { spawn } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { createInterface } from 'readline';

const MCP_SERVER_PATH = process.env.MCP_SERVER_PATH || '/opt/redmica/scripts/mcp-server-wrapper.js';
const OPENCODE_CONFIG = '/root/.config/opencode/opencode.json';

function mask(str) {
  if (!str || str.length < 8) return '***';
  return str.slice(0, 3) + '***' + str.slice(-3);
}

function log(msg) {
  console.error(`[verify] ${msg}`);
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
        log(`Warning: could not parse ${OPENCODE_CONFIG}: ${e.message}`);
      }
    }
  }

  if (!redmineUrl) redmineUrl = 'http://127.0.0.1:4000';

  return { apiKey, redmineUrl };
}

async function promptForApiKey() {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question('[verify] REDMINE_API_KEY not found. Please enter API key: ', (answer) => {
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
    log('ERROR: REDMINE_API_KEY is required.');
    process.exit(1);
  }

  log(`REDMINE_URL: ${redmineUrl}`);
  log(`REDMINE_API_KEY: ${mask(apiKey)}`);
  log(`MCP_SERVER: ${MCP_SERVER_PATH}`);

  if (!existsSync(MCP_SERVER_PATH)) {
    log(`ERROR: MCP server not found at ${MCP_SERVER_PATH}. Run 'npm run build' first.`);
    process.exit(1);
  }

  const env = {
    ...process.env,
    REDMINE_URL: redmineUrl,
    REDMINE_API_KEY: apiKey,
    LOG_LEVEL: 'warn',
  };

  const child = spawn('node', [MCP_SERVER_PATH], {
    env,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  let requestId = 0;
  const pending = new Map();

  function send(method, params) {
    const id = ++requestId;
    const msg = JSON.stringify({ jsonrpc: '2.0', id, method, params });
    log(`→ ${method} (id=${id})`);
    child.stdin.write(msg + '\n');
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`Timeout waiting for response to ${method}`));
      }, 30000);
      pending.set(id, (result) => {
        clearTimeout(timer);
        pending.delete(id);
        resolve(result);
      });
    });
  }

  function sendNotification(method, params) {
    const msg = JSON.stringify({ jsonrpc: '2.0', method, params });
    log(`→ ${method} (notification)`);
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
        } else if (msg.method) {
          log(`← ${msg.method} (stray/notification)`);
        }
      } catch (e) {
        log(`← (unparseable) ${line.slice(0, 200)}`);
      }
    }
  });

  child.stderr.on('data', (data) => {
    const text = data.toString().trim();
    if (text) {
      const first = text.split('\n')[0];
      const safe = first.replaceAll(apiKey, mask(apiKey));
      log(`Server: ${safe}`);
    }
  });

  child.on('error', (err) => {
    log(`Spawn error: ${err.message}`);
    process.exit(1);
  });

  child.on('exit', (code) => {
    if (code !== 0 && code !== null) {
      log(`Server exited unexpectedly with code ${code}`);
    }
  });

  await new Promise((r) => setTimeout(r, 800));

  let success = false;
  let toolCount = 0;
  let projectsNonEmpty = false;

  try {
    const initRes = await send('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'verify-redmine-mcp', version: '1.0.0' },
    });
    if (initRes.error) {
      log(`Initialize failed: ${JSON.stringify(initRes.error)}`);
      throw new Error('Initialize failed');
    }
    log('Initialize: OK');

    sendNotification('notifications/initialized', {});
    log('Initialized notification sent');

    const toolsRes = await send('tools/list', {});
    if (toolsRes.error) {
      log(`tools/list failed: ${JSON.stringify(toolsRes.error)}`);
      throw new Error('tools/list failed');
    }
    const tools = toolsRes.result?.tools || [];
    toolCount = tools.length;
    log(`tools/list: ${toolCount} tools available`);

    const projectsRes = await send('tools/call', {
      name: 'redmine_list_projects',
      arguments: { limit: 5 },
    });
    if (projectsRes.error) {
      log(`redmine_list_projects failed: ${JSON.stringify(projectsRes.error)}`);
      throw new Error('redmine_list_projects failed');
    }
    const contentArr = projectsRes.result?.content || [];
    const text = contentArr.map((c) => (c.type === 'text' ? c.text : '')).join('');
    projectsNonEmpty = text.length > 0 && !text.includes('No projects found') && !text.includes('Error executing');
    log(`redmine_list_projects: ${projectsNonEmpty ? 'non-empty list' : 'empty list or error in response'}`);
    if (!projectsNonEmpty) {
      log(`Response preview: ${text.slice(0, 200).replace(/\n/g, ' ')}`);
    }

    success = true;
  } catch (err) {
    log(`Verification failed: ${err.message}`);
    success = false;
  } finally {
    log('Shutting down MCP server...');
    child.stdin.end();
    child.kill('SIGTERM');
    await new Promise((r) => setTimeout(r, 500));
    if (!child.killed) child.kill('SIGKILL');
  }

  log('--- Summary ---');
  log(`Tools available: ${toolCount}`);
  log(`Projects list non-empty: ${projectsNonEmpty}`);
  log(`Overall: ${success ? 'SUCCESS' : 'FAILURE'}`);

  process.exit(success ? 0 : 1);
}

main().catch((err) => {
  console.error(`[verify] Unhandled error: ${err.message}`);
  process.exit(1);
});
