# iChat

Cross-region **room chat** for World of Warcraft via a **local companion** and a **WebSocket relay**.

WoW addon Lua **cannot** open sockets or HTTP. Native chat is realm/region-scoped. This project does **not** claim otherwise: realtime transport is outside the game client.

## Architecture (MVP)

```
WoW addon  --SavedVariables / Inbox.lua-->  Local companion  --WebSocket-->  Relay server
                 (Sync /reload)              + browser UI                   (rooms)
```

| Piece | Role |
| --- | --- |
| `addon/iChat` | In-game UI: rooms, send/receive mirror, Sync |
| `companion/` | **Required** bridge + **true realtime** local chat UI |
| `server/` | Minimal room relay (broadcast JSON messages) |

**Realtime:** companion browser UI ↔ relay is sub-second WebSocket chat.  
**In-game:** after send/receive batches, click **Sync** (`/reload`) so SavedVariables flush and `Inbox.lua` reloads.

Canonical design notes: Project store `docs/ichat-mvp-plan.md` (when working in the Cursor Project).

## Targets

- **Retail** Interface `120105` (primary)
- **Classic Era** `11509` and **MoP Classic** `50504` (same scaffold)

## Quick start (no WoW required)

Needs Node.js 18+.

```bash
# Terminal 1 — relay
cd server && npm install && npm start
# ws://127.0.0.1:7711   health: http://127.0.0.1:7711/health

# Terminal 2 — companion
cd companion
cp config.example.json config.json   # optional; defaults work for browser-only
npm install && npm start
# open http://127.0.0.1:7712
```

Open the companion UI in two browser profiles/windows, join the same room, send messages — everyone should see sender, room, and timestamp live.

## Load the addon in WoW

1. Copy the folder `addon/iChat` to:
   - Retail: `World of Warcraft/_retail_/Interface/AddOns/iChat`
   - Classic Era: `World of Warcraft/_classic_era_/Interface/AddOns/iChat`
   - MoP Classic: `World of Warcraft/_classic_/Interface/AddOns/iChat` (path may vary by install)
2. Restart the client or wait until AddOns refresh at character select; enable **iChat**.
3. In-game: `/ichat` opens the window; `/ichat help` lists commands.
4. Point the companion at your install (`companion/config.json`):

```json
{
  "relayUrl": "ws://127.0.0.1:7711",
  "httpPort": 7712,
  "sender": "YourName-YourRealm",
  "defaultRoom": "global",
  "wowAddonPath": "C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/iChat",
  "wowSavedVariablesPath": "C:/Program Files (x86)/World of Warcraft/_retail_/WTF/Account/ACCOUNTNAME/SavedVariables/iChat.lua"
}
```

`wowSavedVariablesPath` appears only after the addon has run and you have logged out or Synced once.

### In-game flow

1. Set room → **Join** (or `/ichat room name`).
2. Type a message → **Send** (queued into `IChatDB.outbox`).
3. Click **Sync** so WoW writes SavedVariables; companion reads the outbox and publishes to the relay.
4. When others chat, companion updates `Inbox.lua`; **Sync** again to pull messages into the addon UI.

Day-to-day, use the companion browser UI for live conversation; use the addon as the in-game mirror.

## Protocol (JSON over WebSocket)

```json
{ "type": "join", "room": "global", "sender": "Amin-Realm" }
{ "type": "msg", "room": "global", "sender": "Amin-Realm", "text": "hello", "ts": 1730812345678 }
```

Relay echoes `msg` to everyone in the room (including a short history on join). Companion reconnects with exponential backoff.

## Blizzard policy / ToS — read before shipping

- The **addon** uses only the official sandbox API (normal addon model).
- The **companion + external relay** are third-party software. Blizzard does **not** certify companions. File-based bridges (similar spirit to WeakAuras Companion / TSM desktop tools) are common, but **not** a policy guarantee.
- This MVP **does not** read game memory, inject code into the client, or automate input — by design, to stay on the lower-risk side of companion patterns.
- Running a global chat relay can still conflict with community standards or be used for abuse; if you host a public relay, you own moderation and legal exposure.
- **Account action risk is real** for any third-party tool. Review the current Blizzard EULA / ToS yourself before distributing iChat widely. This README is not legal advice.

## Repo layout

```
addon/iChat/     WoW addon (TOC + Lua)
companion/       Local bridge + http://127.0.0.1:7712 UI
server/          WebSocket room relay
```

## License

MVP scaffold — add a license before a public release if you redistribute.
