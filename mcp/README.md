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

### Run it manually

```sh
node mcp/xcode-mcp-server.js            # listens on 0.0.0.0:9876
PORT=9000 node mcp/xcode-mcp-server.js  # custom port
```

Then point your MCP client at:

```
http://<host-mac-ip>:9876/sse
```

Requirements: macOS with Xcode installed (so `xcrun mcpbridge` exists).

### Run at login with launchd (recommended)

On the host Mac the bridge runs as a per-user **LaunchAgent**
(`com.nickbrett.xcode-mcp-server.plist`), so launchd starts it at login and
keeps it alive on the host — no pm2 and no third-party monitor required.

Install it (copy the script to `/usr/local/bin` first if it isn't there yet):

```sh
cp mcp/xcode-mcp-server.js /usr/local/bin/xcode-mcp-server.js
cp mcp/com.nickbrett.xcode-mcp-server.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nickbrett.xcode-mcp-server.plist
launchctl enable    gui/$(id -u)/com.nickbrett.xcode-mcp-server
```

Operate it:

```sh
# status
launchctl print gui/$(id -u)/com.nickbrett.xcode-mcp-server
# restart
launchctl kickstart -k gui/$(id -u)/com.nickbrett.xcode-mcp-server
# stop + unload
launchctl bootout gui/$(id -u)/com.nickbrett.xcode-mcp-server
# logs
tail -f ~/Library/Logs/xcode-mcp-server.out.log \
        ~/Library/Logs/xcode-mcp-server.err.log
# health check
curl http://127.0.0.1:9876/ping   # -> pong
```

The job also appears in [LaunchControl](https://www.soma-zone.com/LaunchControl/)
and `launchctl`, either of which can load/unload or edit it.

> ℹ️ The committed plist hard-codes this machine's layout: the script at
> `/usr/local/bin/xcode-mcp-server.js`, `node` at `/opt/homebrew/bin/node`, and
> logs under `/Users/nick/Library/Logs`. Adjust those paths for another machine.

> 🕓 **History:** this server was previously run by **pm2**
> (`pm2 start /usr/local/bin/xcode-mcp-server.js --name xcode-mcp`) and watched by
> the **Reeve** menu-bar app. Reeve pegged a CPU core (>80–100%) while polling
> pm2, so the process was migrated to launchd and both pm2 and Reeve were retired.

> ⚠️ **Security:** CORS is wide open and there is no authentication. This is a
> local development helper — only run it on a trusted network.
