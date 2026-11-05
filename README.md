# iChat — Stage 1 realtime GlobalChat

Cross-region GlobalChat for World of Warcraft **without** timed SavedVariables / `/reload` sync loops.

## Architecture

```
/gsay (in-game) → hidden bridge channel → Logs/WoWChatLog.txt
                              ↓ fs.watch (event-driven)
                         Companion  ←→  WebSocket relay  ←→  other players
                              ↓
                    GlobalChat overlay (live send + receive)
```

| Piece | Role |
| --- | --- |
| `addon/iChat` | GlobalChat Chat settings + slash cmds; `LoggingChat` + bridge channel emit |
| `companion/` | **`fs.watch` chatlog** + always-connected **overlay** (no poll loop) |
| `server/` | Room relay |

**Why no ChatFrame live receive:** the sandbox cannot be pushed new Lua data without login/`/reload` or process injection. The overlay is the honest realtime receive surface. Chat settings still configure GlobalChat types/colors in WoW.

**Residual limit:** some clients buffer `WoWChatLog.txt`; in-game outbound then waits on Blizzard’s flush. Overlay send/receive stays sub-second.

## Player flow

1. Start relay + companion; open `http://127.0.0.1:7712` (GlobalChat overlay).
2. Set `wowChatLogPath` in `companion/config.json` to `.../Logs/WoWChatLog.txt`.
3. Install `addon/iChat`; enable GlobalChat types under Chat settings.
4. **Realtime:** chat in the overlay.
5. **From game:** `/gsay` `/gtrade` `/gcity` `/groom` `/gwhisper` — companion picks them up via chatlog watch (no `/ichat sync`).

## Quick start (smoke without WoW)

```bash
cd server && npm install && npm start
cd companion
cp config.example.json config.json
# optional: "wowChatLogPath": "/tmp/WoWChatLog.txt"
npm install && npm start
# overlay: http://127.0.0.1:7712
# inject a fake in-game line:
curl -s -X POST http://127.0.0.1:7712/api/debug/inject-chatlog \
  -H 'content-type: application/json' \
  -d '{"channel":"say","text":"hello from chatlog","sender":"Amin-Realm"}'
```

## ToS

Companion uses file watch + overlay only (no memory injection). Still third-party software — residual account risk. Review Blizzard EULA before shipping.

## Stage 2

Discord DM bridge — deferred; not in this tree.
