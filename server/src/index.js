"use strict";

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.ICHAT_PORT || 7711);
const HOST = process.env.ICHAT_HOST || "0.0.0.0";

/** @typedef {{ room: string, channel?: string, roomName?: string, target?: string, sender: string, text: string, ts: number, id?: string }} ChatMsg */

/** @type {Map<string, Set<import('ws').WebSocket>>} */
const rooms = new Map();

const HISTORY_LIMIT = 50;
/** @type {Map<string, ChatMsg[]>} */
const history = new Map();

function roomSet(name) {
  const key = normalizeRoom(name);
  if (!rooms.has(key)) rooms.set(key, new Set());
  return rooms.get(key);
}

function normalizeRoom(name) {
  return (
    String(name || "global-say")
      .trim()
      .toLowerCase()
      .slice(0, 96) || "global-say"
  );
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
  const isWhisper = obj.channel === "whisper" && obj.target;
  const targetLower = isWhisper ? String(obj.target).toLowerCase() : null;
  const senderLower = isWhisper ? String(obj.sender || "").toLowerCase() : null;

  for (const client of set) {
    if (client === except) continue;
    if (client.readyState !== 1) continue;
    if (isWhisper) {
      const name = String(client.ichatSender || "").toLowerCase();
      if (name !== targetLower && name !== senderLower) continue;
    }
    client.send(raw);
  }
}

function leaveAll(ws) {
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
    version: 2,
    message: "Connected. Join rooms (global-say, global-trade, …) or whisper.",
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
      for (const h of hist) {
        if (h.channel === "whisper" && h.target) {
          const name = sender.toLowerCase();
          if (
            name !== String(h.target).toLowerCase() &&
            name !== String(h.sender || "").toLowerCase()
          ) {
            continue;
          }
        }
        send(ws, { type: "msg", ...h });
      }
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
      const channel = String(msg.channel || "say").toLowerCase();
      let room = msg.room;
      if (!room) {
        if (channel === "whisper") room = "whisper";
        else if (channel === "trade") room = "global-trade";
        else if (channel === "city") room = "global-city";
        else if (channel === "room") room = "room:" + String(msg.roomName || "general").toLowerCase();
        else room = "global-say";
      }
      room = normalizeRoom(room);
      if (!ws.ichatRooms.has(room)) {
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
        channel,
        roomName: msg.roomName ? String(msg.roomName).slice(0, 64) : undefined,
        target: msg.target ? String(msg.target).slice(0, 64) : undefined,
        sender: String(msg.sender || ws.ichatSender || "anon").slice(0, 64),
        text,
        ts: Number(msg.ts) || Date.now(),
      };
      // Whispers: don't put private text in shared history for everyone.
      if (channel !== "whisper") pushHistory(room, payload);
      broadcast(room, payload);
      return;
    }

    send(ws, { type: "error", message: `Unknown type: ${type}` });
  });

  ws.on("close", () => leaveAll(ws));
  ws.on("error", () => leaveAll(ws));
});

const heartbeat = setInterval(() => {
  for (const client of wss.clients) {
    if (!client.isAlive) {
      client.terminate();
      continue;
    }
    client.isAlive = false;
    client.ping();
  }
}, 30000);

wss.on("close", () => clearInterval(heartbeat));

server.listen(PORT, HOST, () => {
  console.log(`[ichat-relay] listening on ws://${HOST}:${PORT}`);
  console.log(`[ichat-relay] health: http://127.0.0.1:${PORT}/health`);
});
