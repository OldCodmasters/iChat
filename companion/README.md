# iChat companion

Local bridge for Stage 1 **realtime** GlobalChat.

- Watches `Logs/WoWChatLog.txt` with **`fs.watch`** (OS file events — **not** a SavedVariables poll timer).
- Stays connected to the relay over WebSocket.
- Serves the **GlobalChat overlay** at `http://127.0.0.1:7712` for live send/receive.

## Run

```bash
cp config.example.json config.json   # set sender + wowChatLogPath
npm install
npm start
```

| Config key | Purpose |
| --- | --- |
| `relayUrl` | Default `ws://127.0.0.1:7711` |
| `httpPort` | Overlay port (default `7712`) |
| `sender` | Your `Name-Realm` on the relay |
| `wowChatLogPath` | Absolute path to `WoWChatLog.txt` |

`/api/health` reports `transport: "chatlog-watch+overlay"` and `polling: false`.

## What this is not

- Not an Inbox.lua / `/reload` sync helper.
- Not a timed outbox scraper.
- Overlay is the **primary live receive surface** (ChatFrame cannot be pushed live without injection).

See the repo root [README.md](../README.md).
