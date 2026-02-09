// Node.js bootloader for neodap debug terminal
// Injected via NODE_OPTIONS=--require=<this-file>
// Opens the inspector and notifies neodap so it can attach before code runs.
//
// Uses spawnSync to do synchronous IPC (like VS Code's js-debug bootloader),
// then blocks with inspector.waitForDebugger() until the debugger attaches.

'use strict';

const inspector = require('inspector');
const { spawnSync } = require('child_process');

const serverPort = process.env.NEODAP_DEBUG_PORT;

// Exit silently if not in a debug terminal
if (!serverPort) {
  return;
}

// Open inspector on random port, don't wait yet
inspector.open(0, '127.0.0.1', false);

const url = inspector.url();
if (!url) {
  return;
}

// Parse inspector port from URL (format: ws://127.0.0.1:PORT/UUID)
const match = url.match(/ws:\/\/[^:]+:(\d+)/);
if (!match) {
  return;
}

const inspectorPort = parseInt(match[1], 10);

// Build payload
const payload = JSON.stringify({
  pid: process.pid,
  inspectorPort: inspectorPort,
  inspectorUrl: url,
  argv: process.argv,
});

// Use spawnSync to synchronously send the inspector port to neodap
// This is the same trick VS Code's js-debug uses - spawn a child process
// that does the network I/O, and wait for it synchronously
// Clear NODE_OPTIONS to prevent recursive bootloader loading in child
const result = spawnSync(process.execPath, ['-e', `
  const net = require('net');
  const payload = ${JSON.stringify(payload)};
  const socket = net.createConnection(${serverPort}, '127.0.0.1');

  socket.on('connect', () => {
    socket.write(payload + '\\n');
  });

  socket.on('data', (data) => {
    const msg = data.toString().trim();
    // Exit with code 0 if attached, 1 otherwise
    process.exit(msg === 'attached' ? 0 : 1);
  });

  socket.on('error', () => {
    process.exit(1);
  });

  // Timeout after 10 seconds
  setTimeout(() => process.exit(1), 10000);
`], {
  stdio: 'inherit',
  timeout: 15000,
  env: { ...process.env, NODE_OPTIONS: '' }, // Clear NODE_OPTIONS to prevent recursive bootloader
});

// If the child exited successfully, the debugger should be attaching
// Now block until it actually connects to our inspector
if (result.status === 0) {
  try {
    inspector.waitForDebugger();
  } catch (e) {
    // Ignore errors - debugger might already be connected
  }
}
