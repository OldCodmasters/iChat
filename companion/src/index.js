"use strict";

/**
 * iChat companion — realtime transport (no SavedVariables poll loop).
 *
 * Outbound from game: fs.watch on Logs/WoWChatLog.txt for |iC| bridge lines.
 * Bidirectional live chat: WebSocket overlay ↔ relay.
 */

const fs = require("fs");
const path = require("path");
const http = require("http");
const { WebSocket, WebSocketServer } = require("ws");

const ROOT = path.join(__dirname, "..");
const CONFIG_PATH = process.env.ICHAT_CONFIG || path.join(ROOT, "config.json");

const DEFAULT_ROOMS = [
  "global-say",
  "global-trade",
  "global-city",
  "whisper",
  "room:general",
];

function loadConfig() {
  const defaults = {
    relayUrl: process.env.ICHAT_RELAY_URL || "ws://127.0.0.1:7711",
    httpPort: Number(process.env.ICHAT_HTTP_PORT || 7712),
    sender: process.env.ICHAT_SENDER || "Companion-Local",
    defaultRoom: process.env.ICHAT_ROOM || "global-say",
    defaultChannel: process.env.ICHAT_CHANNEL || "say",
    wowChatLogPath: process.env.ICHAT_CHATLOG_PATH || "",
    joinRooms: DEFAULT_ROOMS,
  };
  if (fs.existsSync(CONFIG_PATH)) {
    try {
      return { ...defaults, ...JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8")) };
    } catch (err) {
      console.warn("[ichat-companion] bad config.json, using defaults:", err.message);
    }
  }
  return defaults;
}

const config = loadConfig();

/** @type {Map<string, object[]>} */
const roomBuffers = new Map();
const BUFFER_LIMIT = 200;
/** @type {Set<string>} */
const seenBridgeIds = new Set();
/** @type {Set<import('ws').WebSocket>} */
const uiClients = new Set();
/** @type {Set<string>} */
const joinedRooms = new Set();

let relayWs = null;
let backoffMs = 1000;
let currentRoom = config.defaultRoom;
let currentChannel = config.defaultChannel;
let senderName = config.sender;
let chatLogOffset = 0;

function buf(room) {
  const key = String(room || "global-say").toLowerCase();
  if (!roomBuffers.has(key)) roomBuffers.set(key, []);
  return roomBuffers.get(key);
}

function roomFor(item) {
  const ch = item.channel || "say";
  if (ch === "whisper") return "whisper";
  if (ch === "trade") return "global-trade";
  if (ch === "city") return "global-city";
  if (ch === "room") return "room:" + String(item.roomName || "general").toLowerCase();
  return "global-say";
}

function pushMsg(msg) {
  const list = buf(msg.room);
  list.push(msg);
  while (list.length > BUFFER_LIMIT) list.shift();
  const raw = JSON.stringify({ type: "msg", ...msg });
  for (const c of uiClients) {
    if (c.readyState === 1) c.send(raw);
  }
}

function sendToRelay(obj) {
  if (!relayWs || relayWs.readyState !== 1) {
    console.warn("[ichat-companion] relay not connected; drop", obj.type);
    return false;
  }
  relayWs.send(JSON.stringify(obj));
  return true;
}

function ensureJoined(room) {
  const key = String(room || "").toLowerCase();
  if (!key || joinedRooms.has(key)) return;
  joinedRooms.add(key);
  sendToRelay({ type: "join", room: key, sender: senderName });
}

function joinDefaults() {
  for (const r of config.joinRooms || DEFAULT_ROOMS) ensureJoined(r);
  ensureJoined(currentRoom);
}

function broadcastUi(obj) {
  const raw = JSON.stringify(obj);
  for (const c of uiClients) {
    if (c.readyState === 1) c.send(raw);
  }
}

function connectRelay() {
  console.log(`[ichat-companion] connecting to ${config.relayUrl}`);
  const ws = new WebSocket(config.relayUrl);
  relayWs = ws;

  ws.on("open", () => {
    backoffMs = 1000;
    console.log("[ichat-companion] relay connected");
    joinedRooms.clear();
    joinDefaults();
    broadcastUi({
      type: "status",
      connected: true,
      room: currentRoom,
      channel: currentChannel,
      sender: senderName,
    });
  });

  ws.on("message", (data) => {
    let msg;
    try {
      msg = JSON.parse(String(data));
    } catch {
      return;
    }
    if (msg.type === "msg") {
      pushMsg({
        id: msg.id,
        channel: msg.channel || "say",
        room: msg.room,
        roomName: msg.roomName,
        target: msg.target,
        sender: msg.sender,
        text: msg.text,
        ts: msg.ts,
      });
    } else if (
      msg.type === "joined" ||
      msg.type === "hello" ||
      msg.type === "presence" ||
      msg.type === "error"
    ) {
      broadcastUi(msg);
    }
  });

  ws.on("close", () => {
    console.warn(`[ichat-companion] relay closed; retry in ${backoffMs}ms`);
    broadcastUi({ type: "status", connected: false });
    scheduleReconnect();
  });

  ws.on("error", (err) => {
    console.warn("[ichat-companion] relay error:", err.message);
  });
}

function scheduleReconnect() {
  const wait = backoffMs;
  backoffMs = Math.min(backoffMs * 2, 30000);
  setTimeout(connectRelay, wait);
}

/** Parse |iC|1|<channel>|<meta>|<text> from a chatlog line. */
function parseBridgeLine(line) {
  const idx = line.indexOf("|iC|");
  if (idx < 0) return null;
  const payload = line.slice(idx);
  // |iC|1|say||hello world
  const m = payload.match(/^\|iC\|(\d+)\|([^|]*)\|([^|]*)\|(.*)$/);
  if (!m) return null;
  const version = Number(m[1]);
  if (version !== 1) return null;
  const channel = (m[2] || "say").toLowerCase();
  const meta = m[3] || "";
  const text = (m[4] || "").trim();
  if (!text) return null;

  let sender = senderName;
  const before = line.slice(0, idx);
  const names = [...before.matchAll(/\[([^\]]+)\]/g)].map((x) => x[1]);
  if (names.length) {
    const candidate = names[names.length - 1];
    if (!/^iChat/i.test(candidate) && !/^\d/.test(candidate)) {
      sender = candidate;
    }
  }

  const item = {
    channel,
    text,
    sender,
    ts: Date.now(),
  };
  if (channel === "whisper") item.target = meta;
  if (channel === "room") item.roomName = meta || "general";
  item.room = roomFor(item);
  item.id = `log-${item.ts}-${Math.random().toString(36).slice(2, 7)}`;
  return item;
}

function ingestChatLogChunk(chunk) {
  const lines = chunk.split(/\r?\n/);
  for (const line of lines) {
    if (!line || !line.includes("|iC|")) continue;
    const item = parseBridgeLine(line);
    if (!item) continue;
    const dedupe = item.id + "|" + item.text + "|" + item.sender;
    if (seenBridgeIds.has(dedupe)) continue;
    seenBridgeIds.add(dedupe);
    if (seenBridgeIds.size > 2000) {
      const arr = [...seenBridgeIds];
      seenBridgeIds.clear();
      for (const id of arr.slice(-400)) seenBridgeIds.add(id);
    }
    // Prefer configured sender for relay identity when chatlog name is bare.
    if (config.sender && config.sender !== "Companion-Local") {
      item.sender = config.sender;
    }
    ensureJoined(item.room);
    console.log(`[ichat-companion] chatlog → relay ${item.channel}: ${item.text}`);
    sendToRelay({
      type: "msg",
      id: item.id,
      channel: item.channel,
      room: item.room,
      roomName: item.roomName,
      target: item.target,
      sender: item.sender,
      text: item.text,
      ts: item.ts,
    });
  }
}

function readNewChatLogBytes() {
  const p = config.wowChatLogPath;
  if (!p || !fs.existsSync(p)) return;
  let st;
  try {
    st = fs.statSync(p);
  } catch {
    return;
  }
  if (st.size < chatLogOffset) {
    // Log rotated / truncated.
    chatLogOffset = 0;
  }
  if (st.size === chatLogOffset) return;
  const len = st.size - chatLogOffset;
  const fd = fs.openSync(p, "r");
  try {
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, chatLogOffset);
    chatLogOffset = st.size;
    ingestChatLogChunk(buf.toString("utf8"));
  } finally {
    fs.closeSync(fd);
  }
}

function watchChatLog() {
  const p = config.wowChatLogPath;
  if (!p) {
    console.log("[ichat-companion] wowChatLogPath empty — overlay-only mode (no in-game outbound watch)");
    return;
  }

  const dir = path.dirname(p);
  const base = path.basename(p);

  // Start at EOF so we only see new lines (event-driven appends).
  if (fs.existsSync(p)) {
    chatLogOffset = fs.statSync(p).size;
    console.log(`[ichat-companion] watching chatlog ${p} (offset ${chatLogOffset})`);
  } else {
    console.log(`[ichat-companion] chatlog not found yet; watching dir ${dir} for ${base}`);
    chatLogOffset = 0;
  }

  const onChange = () => {
    try {
      readNewChatLogBytes();
    } catch (err) {
      console.warn("[ichat-companion] chatlog read error:", err.message);
    }
  };

  try {
    // Directory watch is more reliable when the log file is recreated.
    if (fs.existsSync(dir)) {
      fs.watch(dir, { persistent: true }, (eventType, filename) => {
        if (filename && filename !== base && String(filename) !== base) return;
        onChange();
      });
    }
    if (fs.existsSync(p)) {
      fs.watch(p, { persistent: true }, () => onChange());
    }
  } catch (err) {
    console.warn("[ichat-companion] fs.watch failed:", err.message);
    console.warn("[ichat-companion] falling back to rare existence checks is not used — fix the path.");
  }
}

function serveStatic(req, res) {
  const url = new URL(req.url, "http://127.0.0.1");
  if (url.pathname === "/api/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        ok: true,
        connected: !!(relayWs && relayWs.readyState === 1),
        room: currentRoom,
        channel: currentChannel,
        sender: senderName,
        chatLogPath: config.wowChatLogPath || null,
        transport: "chatlog-watch+overlay",
        polling: false,
        stage: 1,
      })
    );
    return;
  }

  if (url.pathname === "/api/history") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(buf(currentRoom)));
    return;
  }

  // Test helper: append a synthetic chatlog line (smoke without WoW).
  if (url.pathname === "/api/debug/inject-chatlog" && req.method === "POST") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      let payload;
      try {
        payload = JSON.parse(body || "{}");
      } catch {
        res.writeHead(400);
        res.end("bad json");
        return;
      }
      const line =
        payload.line ||
        `1/1 00:00:00.000  [iChatX] [${payload.sender || senderName}]: |iC|1|${payload.channel || "say"}|${payload.meta || ""}|${payload.text || "test"}`;
      if (config.wowChatLogPath) {
        fs.mkdirSync(path.dirname(config.wowChatLogPath), { recursive: true });
        fs.appendFileSync(config.wowChatLogPath, line + "\n", "utf8");
      } else {
        ingestChatLogChunk(line + "\n");
      }
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    });
    return;
  }

  let file = url.pathname === "/" ? "/index.html" : url.pathname;
  file = path.normalize(file).replace(/^(\.\.[/\\])+/, "");
  const full = path.join(ROOT, "public", file);
  if (!full.startsWith(path.join(ROOT, "public"))) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  fs.readFile(full, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    const ext = path.extname(full);
    const types = {
      ".html": "text/html; charset=utf-8",
      ".js": "text/javascript; charset=utf-8",
      ".css": "text/css; charset=utf-8",
    };
    res.writeHead(200, { "Content-Type": types[ext] || "application/octet-stream" });
    res.end(data);
  });
}

const httpServer = http.createServer(serveStatic);
const uiWss = new WebSocketServer({ server: httpServer });

uiWss.on("connection", (ws) => {
  uiClients.add(ws);
  ws.send(
    JSON.stringify({
      type: "status",
      connected: !!(relayWs && relayWs.readyState === 1),
      room: currentRoom,
      channel: currentChannel,
      sender: senderName,
    })
  );
  for (const m of buf(currentRoom)) {
    ws.send(JSON.stringify({ type: "msg", ...m }));
  }

  ws.on("message", (data) => {
    let msg;
    try {
      msg = JSON.parse(String(data));
    } catch {
      return;
    }
    if (msg.type === "join") {
      currentRoom = String(msg.room || currentRoom).slice(0, 96);
      currentChannel = String(msg.channel || currentChannel).slice(0, 32);
      if (msg.sender) senderName = String(msg.sender).slice(0, 64);
      ensureJoined(currentRoom);
      broadcastUi({
        type: "status",
        connected: true,
        room: currentRoom,
        channel: currentChannel,
        sender: senderName,
      });
      return;
    }
    if (msg.type === "msg") {
      const text = String(msg.text || "").slice(0, 500);
      if (!text.trim()) return;
      const channel = String(msg.channel || currentChannel || "say");
      const room = msg.room || roomFor({ channel, roomName: msg.roomName });
      ensureJoined(room);
      sendToRelay({
        type: "msg",
        channel,
        room,
        roomName: msg.roomName,
        target: msg.target,
        sender: msg.sender || senderName,
        text,
        ts: Date.now(),
      });
    }
  });

  ws.on("close", () => uiClients.delete(ws));
});

httpServer.listen(config.httpPort, "127.0.0.1", () => {
  console.log(`[ichat-companion] GlobalChat overlay http://127.0.0.1:${config.httpPort}`);
  console.log("[ichat-companion] transport=chatlog-watch+overlay polling=false");
});

connectRelay();
watchChatLog();

process.on("SIGINT", () => process.exit(0));
