#!/usr/bin/env node
/**
 * xcode-mcp-server.js
 * ---------------------------------------------------------------------------
 * A tiny local HTTP <-> stdio bridge for the Xcode MCP server.
 *
 * WHY THIS EXISTS
 *   Xcode ships an MCP (Model Context Protocol) server, exposed on macOS via
 *   the command `xcrun mcpbridge`. That process speaks MCP over **stdio**
 *   (newline-delimited JSON-RPC on stdin/stdout), which is fine for a local
 *   client that can spawn a child process -- but a client running inside the
 *   project's dev container (Docker) cannot reach host stdio directly.
 *
 *   This script runs on the host Mac and exposes the stdio bridge over HTTP
 *   using MCP's HTTP+SSE transport, so a containerised client can talk to the
 *   local Xcode MCP server over the network.
 *
 * TRANSPORT / PROTOCOL
 *   It implements the (legacy) MCP "HTTP with SSE" transport:
 *     - GET  /sse       Opens a Server-Sent Events stream. The first event is
 *                       `endpoint`, telling the client which URL to POST to,
 *                       including the session id. Subsequent `message` events
 *                       carry JSON-RPC responses/notifications coming back
 *                       from `xcrun mcpbridge` stdout.
 *     - POST /messages  Accepts a JSON-RPC request body (?sessionId=...) and
 *                       writes it to the matching mcpbridge's stdin.
 *     - GET  /ping      Simple liveness/health check ("pong").
 *
 *   Each SSE connection gets its own `xcrun mcpbridge` child process, keyed by
 *   a session id, so multiple clients/sessions stay isolated. When the SSE
 *   client disconnects (or the child exits), the child is killed and the
 *   session is torn down.
 *
 * USAGE
 *   node xcode-mcp-server.js            # listens on 0.0.0.0:9876
 *   PORT=9000 node xcode-mcp-server.js  # custom port
 *
 *   Point your MCP client at: http://<host-mac-ip>:9876/sse
 *   (On macOS, `xcrun mcpbridge` must be available, i.e. Xcode installed.)
 *
 * NOTE
 *   This is development/infrastructure glue for the stripe-toddler project; it
 *   is not part of the shipping app. CORS is fully open and there is no auth,
 *   so bind it to a trusted dev network only.
 * ---------------------------------------------------------------------------
 */

const http = require('http');
const { spawn } = require('child_process');
const { randomUUID } = require('crypto');

// Port the HTTP bridge listens on (override with the PORT env var).
const PORT = process.env.PORT || 9876;

// Map of sessionId -> { child, sseRes }
// One entry per active SSE connection, holding the paired mcpbridge child
// process and the SSE response stream we push its stdout to.
const sessions = new Map();

function log(...args) {
  console.log(`[${new Date().toISOString()}]`, ...args);
}

function logError(...args) {
  console.error(`[${new Date().toISOString()}]`, ...args);
}

const server = http.createServer((req, res) => {
  // Set CORS headers
  // Wide-open CORS so the dev container / browser-based clients can call this
  // from any origin during local development.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, DELETE');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Access-Control-Expose-Headers', '*');

  // Pre-flight request from a browser client -- answer and bail out.
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  // Health check
  // Cheap liveness probe used to confirm the host bridge is up and reachable
  // from inside the container.
  if (url.pathname === '/ping') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('pong');
    return;
  }

  // GET /sse -> Establish SSE connection and spawn xcrun mcpbridge
  // Starting point for a client session: open an SSE stream, tell the client
  // where to POST, then spawn a dedicated mcpbridge and pipe its stdout here.
  if (req.method === 'GET' && url.pathname === '/sse') {
    const sessionId = randomUUID();
    log(`New SSE connection request. Assigning sessionId: ${sessionId}`);

    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
    });

    // Send endpoint event to tell client where to POST messages
    // Per MCP HTTP+SSE transport: the client learns its POST target (with the
    // session id) from this first `endpoint` event.
    res.write(`event: endpoint\ndata: /messages?sessionId=${sessionId}\n\n`);

    // Send connection established info event
    // Informational notification so the client can see the stream is live.
    const infoMsg = JSON.stringify({
      jsonrpc: "2.0",
      method: "notifications/message",
      params: { data: "SSE Connection established", level: "info" }
    });
    res.write(`event: message\ndata: ${infoMsg}\n\n`);

    // Spawn xcrun mcpbridge
    // The real Xcode MCP server: a local process speaking JSON-RPC over stdio.
    log(`Spawning 'xcrun mcpbridge' for session ${sessionId}`);
    const child = spawn('xcrun', ['mcpbridge'], {
      env: { ...process.env },
      stdio: ['pipe', 'pipe', 'pipe']
    });

    sessions.set(sessionId, { child, sseRes: res });

    // Handle stdout from mcpbridge -> pipe to SSE
    // mcpbridge emits newline-delimited JSON-RPC; buffer partial lines and
    // forward each complete message to the client as an SSE `message` event.
    let stdoutBuffer = '';
    child.stdout.on('data', (chunk) => {
      stdoutBuffer += chunk.toString();
      const lines = stdoutBuffer.split('\n');
      stdoutBuffer = lines.pop(); // Keep incomplete line

      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed) {
          log(`[mcpbridge ${sessionId} stdout]`, trimmed);
          res.write(`event: message\ndata: ${trimmed}\n\n`);
        }
      }
    });

    // Handle stderr from mcpbridge -> log to console
    // Diagnostics only; not part of the MCP wire protocol.
    child.stderr.on('data', (chunk) => {
      logError(`[mcpbridge ${sessionId} stderr]`, chunk.toString().trim());
    });

    // Handle child process close/exit
    // mcpbridge ended (crash, normal exit, or iOS tooling quit): close the SSE
    // stream and forget the session.
    child.on('close', (code, signal) => {
      log(`mcpbridge process for session ${sessionId} closed with code ${code}, signal ${signal}`);
      if (sessions.has(sessionId)) {
        res.end();
        sessions.delete(sessionId);
      }
    });

    child.on('error', (err) => {
      // Most commonly raised when `xcrun`/mcpbridge isn't found on the host.
      logError(`Failed to start mcpbridge for session ${sessionId}:`, err);
      if (!res.writableEnded) {
        res.writeHead(500);
        res.end('Failed to spawn mcpbridge');
      }
      sessions.delete(sessionId);
    });

    // Handle client disconnect
    // Client went away: kill the matching child so we don't leak processes.
    req.on('close', () => {
      log(`SSE client connection closed for session ${sessionId}`);
      if (sessions.has(sessionId)) {
        const session = sessions.get(sessionId);
        try {
          session.child.kill();
        } catch (e) {
          logError(`Error killing child process for session ${sessionId}:`, e);
        }
        sessions.delete(sessionId);
      }
    });

    return;
  }

  // POST /messages?sessionId=... -> Send message to stdin of the associated mcpbridge
  // Inbound half of the bridge: take the client's JSON-RPC request and write it
  // as a newline-terminated line to the session's mcpbridge stdin.
  if (req.method === 'POST' && url.pathname === '/messages') {
    const sessionId = url.searchParams.get('sessionId');
    if (!sessionId) {
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('Missing sessionId');
      return;
    }

    const session = sessions.get(sessionId);
    if (!session) {
      // Unknown or already-torn-down session (e.g. stale client state).
      logError(`POST request for invalid/expired sessionId: ${sessionId}`);
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Session not found or expired');
      return;
    }

    // Collect the request body (streamed in chunks) then forward it.
    const bodyParts = [];
    req.on('data', (chunk) => {
      bodyParts.push(chunk);
    });

    req.on('end', () => {
      const body = Buffer.concat(bodyParts).toString('utf8');
      if (body.trim()) {
        log(`[POST ${sessionId}] writing to child stdin:`, body.trim());
        try {
          session.child.stdin.write(body + '\n');
          res.writeHead(200, { 'Content-Type': 'text/plain' });
          res.end('Accepted');
        } catch (err) {
          logError(`Error writing to mcpbridge stdin for session ${sessionId}:`, err);
          res.writeHead(500, { 'Content-Type': 'text/plain' });
          res.end('Failed to write to stdio');
        }
      } else {
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Empty body');
      }
    });

    return;
  }

  // Fallback 404
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, '0.0.0.0', () => {
  log(`Xcode MCP Proxy server listening on 0.0.0.0:${PORT}`);
});
