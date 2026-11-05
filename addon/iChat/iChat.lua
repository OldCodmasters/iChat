--[[
  iChat core — GlobalChat send via chatlog bridge (event-driven companion watch).

  Live receive is the companion overlay (ChatFrame cannot be pushed without
  /reload or process injection). Chat settings GlobalChat types stay in Channels.lua.
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

--- Send a GlobalChat message (realtime path: bridge channel → chatlog → companion).
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
  if #text > 180 then
    text = text:sub(1, 180)
  end

  if kind == "room" and not opts.roomName then
    opts.roomName = IChat.GetRoomName()
  end

  local entry = {
    id = tostring(now()) .. "-" .. tostring(math.random(1000, 9999)),
    channel = kind,
    room = IChat.RelayRoomFor(kind, opts),
    roomName = opts.roomName,
    target = opts.target,
    sender = playerLabel(),
    text = text,
    ts = now(),
  }

  local ok = IChat.Bridge and IChat.Bridge.Emit(kind, text, opts)
  if not ok then
    print("|cffd4a017iChat|r send failed — bridge channel unavailable.")
    return
  end

  -- Local echo into enabled ChatFrames (outgoing only).
  if IChat.Channels and IChat.Channels.PaintMessage then
    IChat.Channels.PaintMessage(entry)
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
end)

SLASH_ICHAT1 = "/ichat"
SlashCmdList["ICHAT"] = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" or cmd == "help" then
    print("|cffd4a017iChat|r Stage 1 — realtime GlobalChat (no sync loop)")
    print("  Chat settings → GlobalChat: enable types / colors")
    print("  Send in-game: /gsay /gtrade /gcity /groom /gwhisper")
    print("  Live receive: companion GlobalChat overlay (always-connected)")
    print("  /ichat room <name> — default Global Room name")
    print("  Companion must watch Logs/WoWChatLog.txt (fs.watch).")
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
  if cmd == "sync" then
    print("|cffd4a017iChat|r /ichat sync was removed — transport is event-driven (chatlog + overlay), not /reload polling.")
    return
  end
  print("|cffd4a017iChat|r unknown command. /ichat help")
end
