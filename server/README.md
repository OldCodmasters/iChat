# iChat relay

Minimal WebSocket room hub for cross-region GlobalChat.

## Run

```bash
npm install
npm start
# ws://127.0.0.1:7711
# http://127.0.0.1:7711/health
```

Env overrides: `ICHAT_PORT`, `ICHAT_HOST`.

## Rooms

| Channel kind | Room id |
| --- | --- |
| say | `global-say` |
| trade | `global-trade` |
| city | `global-city` |
| room | `room:<name>` |
| whisper | `whisper` (delivered only to matching `target` / sender) |

Clients send JSON: `join`, `msg`, `ping`. See root [README.md](../README.md).

This process does **not** poll WoW files; companions connect here for realtime fan-out.

Releases: run the relay from a GitHub Release source tag (see [`docs/releasing.md`](../docs/releasing.md)).

