--[[
  iChat core — GlobalChat outbox/inbox + Sync.

  Primary UX is Channels.lua (native ChatFrame + Chat settings).
  This file owns SavedVariables bridging to the companion.
]]

IChat = IChat or {}

local function now()
  if GetServerTime then
    return GetServerTime() * 1000
  end
  return (time() or 0) * 1000
end

local function playerLabel()
  local name = UnitName("player") or "Player"
  local realm = GetRealmName and GetRealmName() or "Realm"
  return name .. "-" .. realm
end

function IChat.EnsureDB()
  if type(IChatDB) ~= "table" then
    IChatDB = {}
  end
  IChatDB.roomName = IChatDB.roomName or "general"
  IChatDB.outbox = IChatDB.outbox or {}
  IChatDB.seenInbox = IChatDB.seenInbox or {}
  IChatDB.chat = IChatDB.chat or {}
end

function IChat.GetRoomName()
  IChat.EnsureDB()
  return IChatDB.roomName or "general"
end

function IChat.SetRoomName(name)
  IChat.EnsureDB()
  name = tostring(name or "general"):lower():gsub("%s+", "-"):sub(1, 64)
  if name == "" then
    name = "general"
  end
  IChatDB.roomName = name
  print("|cffd4a017iChat|r Global Room set to |cffffffff" .. name .. "|r")
end

function IChat.TrimOutbox()
  IChat.EnsureDB()
  while #IChatDB.outbox > 50 do
    table.remove(IChatDB.outbox, 1)
  end
end

--- Queue a GlobalChat message for the companion.
-- @param kind whisper|room|say|trade|city
-- @param text message body
-- @param opts optional { target=, roomName= }
function IChat.SendChannel(kind, text, opts)
  IChat.EnsureDB()
  opts = opts or {}
  text = strtrim(text or "")
  if text == "" then
    return
  end
  if #text > 500 then
    text = text:sub(1, 500)
  end

  local id = tostring(now()) .. "-" .. tostring(math.random(1000, 9999))
  local entry = {
    id = id,
    channel = kind,
    room = IChat.RelayRoomFor(kind, opts),
    roomName = opts.roomName or (kind == "room" and IChat.GetRoomName() or nil),
    target = opts.target,
    sender = playerLabel(),
    text = text,
    ts = now(),
  }

  table.insert(IChatDB.outbox, {
    id = entry.id,
    channel = entry.channel,
    room = entry.room,
    roomName = entry.roomName,
    target = entry.target,
    text = entry.text,
    ts = entry.ts,
  })
  IChat.TrimOutbox()

  -- Echo locally immediately (optimistic UI).
  if IChat.Channels and IChat.Channels.PaintMessage then
    IChat.Channels.PaintMessage(entry)
  end

  print("|cffd4a017iChat|r queued |cffffffff" .. kind .. "|r — click Sync (/ichat sync) so the companion can send it.")
end

function IChat.RelayRoomFor(kind, opts)
  opts = opts or {}
  if kind == "whisper" then
    return "whisper"
  end
  if kind == "room" then
    local n = opts.roomName or IChat.GetRoomName()
    return "room:" .. tostring(n):lower()
  end
  if kind == "trade" then
    return "global-trade"
  end
  if kind == "city" then
    return "global-city"
  end
  return "global-say"
end

function IChat.MergeInbox()
  IChat.EnsureDB()
  if type(IChatInbox) ~= "table" then
    return 0
  end
  local added = 0
  local me = string.lower(playerLabel())
  for _, m in ipairs(IChatInbox) do
    local id = m.id or (tostring(m.ts or 0) .. "|" .. tostring(m.sender) .. "|" .. tostring(m.text))
    if not IChatDB.seenInbox[id] then
      IChatDB.seenInbox[id] = true
      local channel = m.channel or "say"
      -- Whisper filter: show if we are sender or target.
      if channel == "whisper" and m.target then
        local t = string.lower(tostring(m.target))
        local s = string.lower(tostring(m.sender or ""))
        if t ~= me and s ~= me then
          -- still mark seen; not for this character
        else
          if IChat.Channels then
            IChat.Channels.PaintMessage(m)
          end
          added = added + 1
        end
      else
        if IChat.Channels then
          IChat.Channels.PaintMessage(m)
        end
        added = added + 1
      end
    end
  end
  local n = 0
  for _ in pairs(IChatDB.seenInbox) do
    n = n + 1
  end
  if n > 500 then
    IChatDB.seenInbox = {}
  end
  return added
end

function IChat.Sync()
  if C_UI and C_UI.Reload then
    C_UI.Reload()
  else
    ReloadUI()
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name ~= "iChat" then
    return
  end
  IChat.EnsureDB()
  if event == "PLAYER_LOGIN" then
    local n = IChat.MergeInbox()
    if n > 0 then
      print("|cffd4a017iChat|r merged " .. n .. " GlobalChat message(s) from companion inbox.")
    end
  end
end)

SLASH_ICHAT1 = "/ichat"
SlashCmdList["ICHAT"] = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" or cmd == "help" then
    print("|cffd4a017iChat|r Stage 1 — GlobalChat (no separate window)")
    print("  Chat settings → GlobalChat: enable Global Whisper/Room/Say/Trade/City")
    print("  /gsay /gtrade /gcity <msg>")
    print("  /groom [roomname] <msg>   (default room: " .. IChat.GetRoomName() .. ")")
    print("  /gwhisper <Player-Realm> <msg>")
    print("  /ichat sync — flush outbox / load inbox (required companion bridge)")
    print("  /ichat room <name> — set default Global Room name")
    print("  Companion + relay required for cross-region delivery.")
    return
  end
  if cmd == "sync" then
    IChat.Sync()
    return
  end
  if cmd == "room" then
    if rest == "" then
      print("|cffd4a017iChat|r current Global Room: " .. IChat.GetRoomName())
    else
      IChat.SetRoomName(rest)
    end
    return
  end
  print("|cffd4a017iChat|r unknown command. /ichat help")
end
