# `mcp/` — local dev tooling

Infrastructure that supports the developer setup for stripe-toddler. Nothing
here ships with the app.

## `xcode-mcp-server.js`

A tiny **HTTP ⇄ stdio bridge** for the Xcode MCP server.

Xcode exposes its MCP server on macOS via `xcrun mcpbridge`, which speaks MCP
over **stdio** (newline-delimited JSON-RPC on stdin/stdout). A client running
inside the project's **dev container** can't reach host stdio, so this script
runs on the host Mac and re-exposes that stdio bridge over **HTTP + SSE**
(MCP's HTTP-with-SSE transport).

```
┌──────────────────────┐        HTTP + SSE         ┌─────────────────────────┐
│  MCP client in the   │  GET  /sse                │  xcode-mcp-server.js    │
│  dev container       │ ────────────────────────► │  (host Mac)             │
│                      │  POST /messages?...       │                         │
│                      │ ────────────────────────► │        │                │
└──────────────────────┘                           │        ▼ stdin/stdout   │
                                                   │  `xcrun mcpbridge`      │
                                                   │  (Xcode MCP server)     │
                                                   └─────────────────────────┘
```

### Endpoints

| Method | Path        | Purpose                                                        |
| ------ | ----------- | -------------------------------------------------------------- |
| GET    | `/sse`      | Open an SSE session; emits `endpoint` + `message` events.      |
| POST   | `/messages` | Send a JSON-RPC request to a session (`?sessionId=...`).       |
| GET    | `/ping`     | Liveness check — returns `pong`.                               |

Each SSE connection spawns its own `xcrun mcpbridge` child process, keyed by a
session id, so sessions stay isolated. On client disconnect (or child exit) the
child is killed and the session is cleaned up.

### Run it

```sh
node mcp/xcode-mcp-server.js            # listens on 0.0.0.0:9876
PORT=9000 node mcp/xcode-mcp-server.js  # custom port
```

Then point your MCP client at:

```
http://<host-mac-ip>:9876/sse
```

Requirements: macOS with Xcode installed (so `xcrun mcpbridge` exists).

> ⚠️ **Security:** CORS is wide open and there is no authentication. This is a
> local development helper — only run it on a trusted network.
