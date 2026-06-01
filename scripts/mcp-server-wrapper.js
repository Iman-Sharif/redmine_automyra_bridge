#!/usr/bin/env node
const originalSetEncoding = process.stdin.setEncoding.bind(process.stdin);
process.stdin.setEncoding = function(encoding) {
  if (encoding === 'utf8') {
    console.error(`[wrapper] Suppressed process.stdin.setEncoding('${encoding}') to keep raw Buffer mode`);
    return process.stdin;
  }
  return originalSetEncoding(encoding);
};

import { runServer } from '/opt/redmica/redmine-mcp-server-src/dist/server.js';

const logError = (context, error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[wrapper] ${context}: ${message}`);
};

process.on('uncaughtException', (error) => {
  logError('Uncaught exception', error);
  setTimeout(() => process.exit(1), 100);
});

process.on('unhandledRejection', (error) => {
  logError('Unhandled rejection', error);
  setTimeout(() => process.exit(1), 100);
});

(async () => {
  try {
    await runServer();
  } catch (error) {
    logError('Failed to start server', error);
    process.exit(1);
  }
})();
