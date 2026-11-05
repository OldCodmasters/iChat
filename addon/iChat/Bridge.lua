--[[
  Bridge — event-driven outbound to the local companion via chat logging.

  Flow: SendChatMessage → hidden channel → Logs/WoWChatLog.txt
        Companion uses fs.watch (not a timer poll) to read new lines.

  Inbound live ChatFrame injection is impossible without /reload or process
  injection; receive stays on the companion GlobalChat overlay.
]]

IChat = IChat or {}
IChat.Bridge = IChat.Bridge or {}

local B = IChat.Bridge

B.CHANNEL_NAME = "iChatX"
B.CHANNEL_PASS = "ichat-bridge-v1"
B.PREFIX = "|iC|1|"

local joined = false
local channelId

local function ensureLogging()
  if LoggingChat then
    if not LoggingChat() then
      LoggingChat(1)
    end
  end
end

local function hideBridgeChannelFromFrames()
  local name = B.CHANNEL_NAME
  local num = NUM_CHAT_WINDOWS or 10
  for i = 1, num do
    local frame = _G["ChatFrame" .. i]
    if frame and ChatFrame_RemoveChannel then
      pcall(ChatFrame_RemoveChannel, frame, name)
    end
  end
end

function B.Join()
  ensureLogging()
  if JoinPermanentChannel then
    local id = JoinPermanentChannel(B.CHANNEL_NAME, B.CHANNEL_PASS, nil, false)
    if id and id > 0 then
      channelId = id
      joined = true
    end
  end
  -- Resolve id even if already joined from a previous session.
  if GetChannelName then
    local id = GetChannelName(B.CHANNEL_NAME)
    if id and id > 0 then
      channelId = id
      joined = true
    end
  end
  hideBridgeChannelFromFrames()
end

-- Strip bridge traffic from the player's chat windows.
local function bridgeFilter(_, event, msg, _, _, _, _, _, _, _, channelName)
  if channelName and tostring(channelName):lower() == B.CHANNEL_NAME:lower() then
    return true
  end
  if msg and msg:find("|iC|", 1, true) then
    return true
  end
  return false
end

function B.InstallFilter()
  if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", bridgeFilter)
  end
end

local function sanitizeField(s)
  s = tostring(s or "")
  s = s:gsub("|", "/"):gsub("%s+", " ")
  return s:sub(1, 80)
end

local function sanitizeText(s)
  s = tostring(s or "")
  s = s:gsub("|", "/"):gsub("[\r\n]", " ")
  return s:sub(1, 180)
end

--- Emit one outbound GlobalChat line for the companion chatlog watcher.
-- @param kind say|trade|city|room|whisper
-- @param text body
-- @param opts { target=, roomName= }
-- @return boolean ok
function B.Emit(kind, text, opts)
  opts = opts or {}
  ensureLogging()
  if not joined or not channelId or channelId == 0 then
    B.Join()
  end
  if not channelId or channelId == 0 then
    print("|cffd4a017iChat|r could not join bridge channel " .. B.CHANNEL_NAME .. " — is chat restricted?")
    return false
  end

  local meta = ""
  if kind == "whisper" then
    meta = sanitizeField(opts.target)
  elseif kind == "room" then
    meta = sanitizeField(opts.roomName or IChat.GetRoomName())
  end

  local payload = B.PREFIX .. sanitizeField(kind) .. "|" .. meta .. "|" .. sanitizeText(text)
  -- Keep under typical 255 chat limit.
  if #payload > 250 then
    payload = payload:sub(1, 250)
  end

  if SendChatMessage then
    SendChatMessage(payload, "CHANNEL", nil, channelId)
    return true
  end
  return false
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("CHANNEL_UI_UPDATE")
boot:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    B.InstallFilter()
    B.Join()
    ensureLogging()
    print("|cffd4a017iChat|r bridge armed — chat logging on; companion watches WoWChatLog.txt (no sync loop).")
  elseif event == "CHANNEL_UI_UPDATE" then
    hideBridgeChannelFromFrames()
  end
end)
