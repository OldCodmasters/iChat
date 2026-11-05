--[[
  iChat core — queues outbound messages into SavedVariables and merges
  companion-written IChatInbox after Sync (/reload).

  The WoW Lua sandbox cannot open sockets or HTTP. Realtime transport lives
  in the local companion + relay. See README.md.
]]

local ADDON = ...
IChat = IChat or {}

local function now()
  -- GetServerTime is unix seconds on modern clients; fall back to time().
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
  IChatDB.room = IChatDB.room or "global"
  IChatDB.messages = IChatDB.messages or {}
  IChatDB.outbox = IChatDB.outbox or {}
  IChatDB.seenInbox = IChatDB.seenInbox or {}
end

function IChat.TrimMessages()
  IChat.EnsureDB()
  while #IChatDB.messages > 150 do
    table.remove(IChatDB.messages, 1)
  end
  while #IChatDB.outbox > 50 do
    table.remove(IChatDB.outbox, 1)
  end
end

function IChat.AddLocalMessage(entry)
  IChat.EnsureDB()
  table.insert(IChatDB.messages, entry)
  IChat.TrimMessages()
  if IChat.UI and IChat.UI.Refresh then
    IChat.UI.Refresh()
  end
end

function IChat.MergeInbox()
  IChat.EnsureDB()
  if type(IChatInbox) ~= "table" then
    return 0
  end
  local added = 0
  for _, m in ipairs(IChatInbox) do
    local id = m.id or (tostring(m.ts or 0) .. "|" .. tostring(m.sender) .. "|" .. tostring(m.text))
    if not IChatDB.seenInbox[id] then
      IChatDB.seenInbox[id] = true
      IChat.AddLocalMessage({
        id = id,
        room = m.room or IChatDB.room,
        sender = m.sender or "?",
        text = m.text or "",
        ts = tonumber(m.ts) or now(),
        source = "inbox",
      })
      added = added + 1
    end
  end
  -- Bound seen map
  local n = 0
  for _ in pairs(IChatDB.seenInbox) do
    n = n + 1
  end
  if n > 500 then
    IChatDB.seenInbox = {}
  end
  return added
end

function IChat.Send(text)
  IChat.EnsureDB()
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
    room = IChatDB.room or "global",
    sender = playerLabel(),
    text = text,
    ts = now(),
    source = "local",
  }

  table.insert(IChatDB.outbox, {
    id = id,
    room = entry.room,
    text = text,
    ts = entry.ts,
  })
  IChat.AddLocalMessage(entry)
  print("|cffd4a017iChat|r queued for companion. Click |cffffffffSync|r so SavedVariables flush to disk.")
end

function IChat.SetRoom(room)
  IChat.EnsureDB()
  room = strtrim(room or "")
  if room == "" then
    room = "global"
  end
  IChatDB.room = room:lower():sub(1, 64)
  print("|cffd4a017iChat|r room set to |cffffffff#" .. IChatDB.room .. "|r")
  if IChat.UI and IChat.UI.Refresh then
    IChat.UI.Refresh()
  end
end

function IChat.Sync()
  -- Hardware-event gated on modern clients when called from a button OnClick.
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
  if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
    IChat.EnsureDB()
    local n = IChat.MergeInbox()
    if event == "PLAYER_LOGIN" then
      print("|cffd4a017iChat|r loaded. /ichat — companion required for cross-region relay.")
      if n > 0 then
        print("|cffd4a017iChat|r merged " .. n .. " inbox message(s).")
      end
    end
  end
end)

SLASH_ICHAT1 = "/ichat"
SlashCmdList["ICHAT"] = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" or cmd == "show" then
    if IChat.UI and IChat.UI.Toggle then
      IChat.UI.Toggle()
    end
    return
  end
  if cmd == "room" then
    IChat.SetRoom(rest)
    return
  end
  if cmd == "send" then
    IChat.Send(rest)
    return
  end
  if cmd == "sync" then
    IChat.Sync()
    return
  end
  if cmd == "help" then
    print("|cffd4a017iChat|r commands:")
    print("  /ichat — toggle window")
    print("  /ichat room <name> — set room")
    print("  /ichat send <text> — queue message")
    print("  /ichat sync — reload UI (flush outbox / load inbox)")
    return
  end
  -- Bare text after /ichat sends
  IChat.Send(msg)
end
