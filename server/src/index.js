"use strict";

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.ICHAT_PORT || 7711);
const HOST = process.env.ICHAT_HOST || "0.0.0.0";

/** @typedef {{ room: string, sender: string, text: string, ts: number, id?: string }} ChatMsg */

/** @type {Map<string, Set<import('ws').WebSocket>>} */
const rooms = new Map();

/** Keep a short ring buffer per room for late joiners (MVP convenience). */
const HISTORY_LIMIT = 50;
/** @type {Map<string, ChatMsg[]>} */
const history = new Map();

function roomSet(name) {
  const key = normalizeRoom(name);
  if (!rooms.has(key)) rooms.set(key, new Set());
  return rooms.get(key);
}

function normalizeRoom(name) {
  return String(name || "global")
    .trim()
    .toLowerCase()
    .slice(0, 64) || "global";
}

function pushHistory(room, msg) {
  if (!history.has(room)) history.set(room, []);
  const list = history.get(room);
  list.push(msg);
  while (list.length > HISTORY_LIMIT) list.shift();
}

function send(ws, obj) {
  if (ws.readyState === 1) ws.send(JSON.stringify(obj));
}

function broadcast(room, obj, except) {
  const set = rooms.get(room);
  if (!set) return;
  const raw = JSON.stringify(obj);
  for (const client of set) {
    if (client !== except && client.readyState === 1) client.send(raw);
  }
}

function leaveAll(ws) {
  /** @type {Set<string>|undefined} */
  const joined = ws.ichatRooms;
  if (!joined) return;
  for (const room of joined) {
    const set = rooms.get(room);
    if (!set) continue;
    set.delete(ws);
    if (set.size === 0) rooms.delete(room);
  }
  joined.clear();
}

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        ok: true,
        service: "ichat-relay",
        rooms: rooms.size,
        clients: [...rooms.values()].reduce((n, s) => n + s.size, 0),
      })
    );
    return;
  }
  res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("iChat relay — connect via WebSocket\n");
});

const wss = new WebSocketServer({ server });

wss.on("connection", (ws) => {
  ws.ichatRooms = new Set();
  ws.isAlive = true;

  send(ws, {
    type: "hello",
    service: "ichat-relay",
    version: 1,
    message: "Connected. Send {type:'join', room, sender}.",
  });

  ws.on("pong", () => {
    ws.isAlive = true;
  });

  ws.on("message", (data) => {
    let msg;
    try {
      msg = JSON.parse(String(data));
    } catch {
      send(ws, { type: "error", message: "Invalid JSON" });
      return;
    }

    const type = msg && msg.type;
    if (type === "ping") {
      send(ws, { type: "pong", ts: Date.now() });
      return;
    }

    if (type === "join") {
      const room = normalizeRoom(msg.room);
      const sender = String(msg.sender || "anon").slice(0, 64);
      ws.ichatSender = sender;
      roomSet(room).add(ws);
      ws.ichatRooms.add(room);
      send(ws, { type: "joined", room, sender });
      const hist = history.get(room) || [];
      for (const h of hist) send(ws, { type: "msg", ...h });
      broadcast(room, { type: "presence", room, sender, event: "join" }, ws);
      return;
    }

    if (type === "leave") {
      const room = normalizeRoom(msg.room);
      const set = rooms.get(room);
      if (set) {
        set.delete(ws);
        if (set.size === 0) rooms.delete(room);
      }
      ws.ichatRooms.delete(room);
      send(ws, { type: "left", room });
      return;
    }

    if (type === "msg") {
      const room = normalizeRoom(msg.room);
      if (!ws.ichatRooms.has(room)) {
        // Auto-join so a single msg works from thin clients.
        roomSet(room).add(ws);
        ws.ichatRooms.add(room);
      }
      const text = String(msg.text || "").slice(0, 500);
      if (!text.trim()) {
        send(ws, { type: "error", message: "Empty message" });
        return;
      }
      const payload = {
        type: "msg",
        id: msg.id || `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        room,
        sender: String(msg.sender || ws.ichatSender || "anon").slice(0, 64),
        text,
        ts: Number(msg.ts) || Date.now(),
      };
      pushHistory(room, payload);
      // Echo to sender + everyone else in the room.
      broadcast(room, payload);
      return;
    }

    send(ws, { type: "error", message: `Unknown type: ${type}` });
  });

  ws.on("close", () => leaveAll(ws));
  ws.on("error", () => leaveAll(ws));
});

const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, 30000);

wss.on("close", () => clearInterval(heartbeat));

server.listen(PORT, HOST, () => {
  console.log(`[ichat-relay] listening on ws://${HOST}:${PORT}`);
  console.log(`[ichat-relay] health: http://127.0.0.1:${PORT}/health`);
});
