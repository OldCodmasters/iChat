# iChat — Stage 1 GlobalChat

Cross-region chat for World of Warcraft that lives in the **normal chat UI**.

Players enable **GlobalChat** types under Chat settings and talk with `/gsay`, `/gtrade`, `/gcity`, `/groom`, `/gwhisper`. There is **no** separate iChat messenger window as the primary UX.

WoW Lua **cannot** open sockets or HTTP. Delivery uses a **local companion** + **WebSocket relay**. Global\* types are **simulated** chat types (they look configurable like native message groups) but are **not** real Blizzard realm channels.

## Stage roadmap

| Stage | What | Status |
| --- | --- | --- |
| **1** | GlobalChat in Chat settings + companion + relay | **This repo** |
| **2** | Discord DM bridge | **Deferred** — not implemented |

## Architecture

```
ChatFrame / slash commands  →  SavedVariables outbox  →  Companion  →  Relay
ChatFrame ← AddMessage      ←  Inbox.lua (after Sync)  ←  Companion  ←  Relay
```

| Piece | Role |
| --- | --- |
| `addon/iChat` | Registers GlobalChat types, Chat settings section, slash cmds, ChatFrame output |
| `companion/` | **Required** file bridge + reconnecting WS client (browser UI = fallback only) |
| `server/` | Room relay (`global-say`, `global-trade`, `global-city`, `room:*`, `whisper`) |

## GlobalChat channels

| Chat settings label | Slash | Relay |
| --- | --- | --- |
| Global Whisper | `/gwhisper Player-Realm msg` · `/gw` | `whisper` + target filter |
| Global Room | `/groom [name] msg` · `/gr` | `room:<name>` |
| Global Say | `/gsay msg` · `/gs` | `global-say` |
| Global Trade | `/gtrade msg` · `/gt` | `global-trade` |
| Global City | `/gcity msg` · `/gci` | `global-city` |

Open **Chat** settings (chat window gear / Esc → Options → Chat) and use the **GlobalChat** section to toggle which chat tabs show each type and set colors.

### API limits (honest)

- Cannot create true cross-region Blizzard channels.
- Cannot fire real `CHAT_MSG_SAY` / Trade events for other regions.
- Custom types need SavedVariables persistence hooks (Blizzard CVars ignore unknown types).
- In-game delivery still needs **`/ichat sync`** (`/reload`) so the companion can read the outbox / the addon can load `Inbox.lua`. Companion WebSocket traffic itself is realtime.

## Quick start (no WoW)

Node.js 18+.

```bash
cd server && npm install && npm start
# ws://127.0.0.1:7711

cd companion && cp config.example.json config.json && npm install && npm start
# fallback UI http://127.0.0.1:7712
```

## Load the addon

1. Copy `addon/iChat` → `World of Warcraft/_retail_/Interface/AddOns/iChat` (or Classic `_classic_era_` / `_classic_`).
2. Enable **iChat** at character select.
3. Point companion `config.json` at:
   - `wowAddonPath`: `.../Interface/AddOns/iChat`
   - `wowSavedVariablesPath`: `.../WTF/Account/<ACCOUNT>/SavedVariables/iChat.lua` (appears after first Sync/logout)
4. In-game: enable GlobalChat types in Chat settings; send with `/gsay` etc.; **`/ichat sync`** to flush/load.

## Blizzard policy / ToS

- Addon sandbox usage is normal.
- Companion + relay are third-party (not Blizzard-approved). Residual account risk.
- Stage 1 avoids memory reading, injection, and input automation.
- Review current EULA/ToS before distributing. Not legal advice.

## License

MVP scaffold — add a license before public redistribution.
