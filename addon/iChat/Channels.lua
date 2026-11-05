--[[
  GlobalChat — simulated chat types that appear in Chat settings and print
  into the normal ChatFrame. Traffic is NOT Blizzard chat; it routes through
  the local companion + WebSocket relay.

  API honesty:
  - We register ChatTypeGroup / ChatTypeInfo and inject a GlobalChat checkbox
    section into ChatConfig (same family of hooks as custom chat types).
  - Blizzard will not persist unknown types in its CVars; we hook
    Get/Add/RemoveChatWindowMessages + ChangeChatColor into IChatDB.
  - We cannot emit real CHAT_MSG_SAY / Trade channel events cross-region.
]]

IChat = IChat or {}
IChat.Channels = IChat.Channels or {}

local C = IChat.Channels

-- Display order under the GlobalChat ChatConfig section.
C.LIST = {
  { key = "GLOBAL_WHISPER", label = "Global Whisper", slash = { "gwhisper", "gw" }, sticky = 1, flash = true,  r = 1.00, g = 0.50, b = 1.00, kind = "whisper" },
  { key = "GLOBAL_ROOM",    label = "Global Room",    slash = { "groom", "gr" },    sticky = 1, flash = false, r = 0.40, g = 0.85, b = 1.00, kind = "room" },
  { key = "GLOBAL_SAY",     label = "Global Say",     slash = { "gsay", "gs" },     sticky = 1, flash = false, r = 1.00, g = 1.00, b = 1.00, kind = "say" },
  { key = "GLOBAL_TRADE",   label = "Global Trade",   slash = { "gtrade", "gt" },   sticky = 1, flash = false, r = 1.00, g = 0.75, b = 0.25, kind = "trade" },
  { key = "GLOBAL_CITY",    label = "Global City",    slash = { "gcity", "gci" },   sticky = 1, flash = false, r = 0.30, g = 1.00, b = 0.55, kind = "city" },
}

C.BY_KEY = {}
C.BY_KIND = {}
for _, def in ipairs(C.LIST) do
  C.BY_KEY[def.key] = def
  C.BY_KIND[def.kind] = def
end

local function ensureChatDB()
  IChat.EnsureDB()
  if type(IChatDB.chat) ~= "table" then
    IChatDB.chat = {}
  end
  for _, def in ipairs(C.LIST) do
    local slot = IChatDB.chat[def.key]
    if type(slot) ~= "table" then
      slot = {
        r = def.r, g = def.g, b = def.b,
        -- Default: show on chat window 1
        [1] = true,
      }
      IChatDB.chat[def.key] = slot
    end
    if slot.r == nil then slot.r = def.r end
    if slot.g == nil then slot.g = def.g end
    if slot.b == nil then slot.b = def.b end
  end
end

local function isOurType(chattype)
  return chattype and C.BY_KEY[chattype] ~= nil
end

local function listeningOn(chattype, windowId)
  ensureChatDB()
  local slot = IChatDB.chat[chattype]
  return slot and slot[windowId] and true or false
end

local function setListening(chattype, windowId, on)
  ensureChatDB()
  local slot = IChatDB.chat[chattype]
  if not slot then
    return
  end
  slot[windowId] = on and true or false
end

------------------------------------------------------------------------
-- Register types with FrameXML tables + slash / edit-box strings
------------------------------------------------------------------------

function C.RegisterTypes()
  ensureChatDB()

  for _, def in ipairs(C.LIST) do
    local key = def.key
    local slot = IChatDB.chat[key]

    _G["CHAT_MSG_" .. key] = def.label
    _G[key] = def.label
    _G["CHAT_" .. key .. "_GET"] = def.label .. ": "
    _G["CHAT_" .. key .. "_SEND"] = def.label .. ": "

    ChatTypeGroup[key] = { "CHAT_MSG_" .. key }
    if ChatTypeGroupInverted then
      ChatTypeGroupInverted["CHAT_MSG_" .. key] = key
    end

    local info = ChatTypeInfo[key]
    if not info then
      info = {}
      ChatTypeInfo[key] = info
    end
    info.r = slot.r
    info.g = slot.g
    info.b = slot.b
    info.sticky = def.sticky
    info.flashTab = def.flash and true or false
    info.flashTabOnGeneral = def.flash and true or false
    if not info.id and GetChatTypeIndex then
      -- Best-effort; some clients assign ids only for built-ins.
      pcall(function()
        info.id = GetChatTypeIndex(key)
      end)
    end
  end
end

------------------------------------------------------------------------
-- Persist unknown chat types (Blizzard CVars ignore them)
------------------------------------------------------------------------

function C.HookPersistence()
  if C._hooksInstalled then
    return
  end
  C._hooksInstalled = true

  local origGet = GetChatWindowMessages
  function GetChatWindowMessages(n)
    local ret = { origGet(n) }
    ensureChatDB()
    for _, def in ipairs(C.LIST) do
      if listeningOn(def.key, n) then
        table.insert(ret, def.key)
      end
    end
    return unpack(ret)
  end

  local origAdd = AddChatWindowMessages
  function AddChatWindowMessages(n, chattype)
    if isOurType(chattype) then
      setListening(chattype, n, true)
      local frame = _G["ChatFrame" .. n]
      if frame and ChatFrame_AddMessageGroup then
        -- Keep messageTypeList in sync without double-calling Add CVar.
        local list = frame.messageTypeList
        if list then
          local found
          for i = 1, #list do
            if list[i] == chattype then
              found = true
              break
            end
          end
          if not found then
            table.insert(list, chattype)
          end
        end
      end
      return
    end
    return origAdd(n, chattype)
  end

  local origRemove = RemoveChatWindowMessages
  function RemoveChatWindowMessages(n, chattype)
    if isOurType(chattype) then
      setListening(chattype, n, false)
      local frame = _G["ChatFrame" .. n]
      if frame and frame.messageTypeList then
        for i = #frame.messageTypeList, 1, -1 do
          if frame.messageTypeList[i] == chattype then
            table.remove(frame.messageTypeList, i)
          end
        end
      end
      return
    end
    return origRemove(n, chattype)
  end

  local origColor = ChangeChatColor
  function ChangeChatColor(chattype, r, g, b)
    if isOurType(chattype) then
      ensureChatDB()
      local slot = IChatDB.chat[chattype]
      slot.r, slot.g, slot.b = r, g, b
      local info = ChatTypeInfo[chattype]
      if info then
        info.r, info.g, info.b = r, g, b
      end
      return
    end
    return origColor(chattype, r, g, b)
  end
end

------------------------------------------------------------------------
-- Apply listening state onto chat frames after login
------------------------------------------------------------------------

function C.ApplyToChatFrames()
  ensureChatDB()
  local num = NUM_CHAT_WINDOWS or 10
  for i = 1, num do
    local frame = _G["ChatFrame" .. i]
    if frame then
      for _, def in ipairs(C.LIST) do
        if listeningOn(def.key, i) then
          local list = frame.messageTypeList
          local found
          if list then
            for j = 1, #list do
              if list[j] == def.key then
                found = true
                break
              end
            end
            if not found then
              table.insert(list, def.key)
            end
          end
        end
      end
    end
  end
end

------------------------------------------------------------------------
-- Chat settings: GlobalChat section
------------------------------------------------------------------------

local function makeConfigEntry(def)
  return {
    text = def.label,
    type = def.key,
    noClassColor = 1,
    checked = function()
      local id = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame():GetID() or 1
      return listeningOn(def.key, id)
    end,
    func = function(_, checked)
      local id = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame():GetID() or 1
      if checked then
        AddChatWindowMessages(id, def.key)
      else
        RemoveChatWindowMessages(id, def.key)
      end
    end,
  }
end

function C.InstallChatConfigSection()
  if C._configInstalled then
    return
  end
  C._configInstalled = true

  ICHAT_CONFIG_GLOBALCHAT = {}
  for i, def in ipairs(C.LIST) do
    ICHAT_CONFIG_GLOBALCHAT[i] = makeConfigEntry(def)
  end

  local function buildPanel()
    if not ChatConfigFrame or not ChatConfigChatSettings then
      return
    end
    if _G.iChatGlobalChatSettings then
      if ChatConfig_CreateCheckboxes then
        ChatConfig_CreateCheckboxes(
          _G.iChatGlobalChatSettings,
          ICHAT_CONFIG_GLOBALCHAT,
          "ChatConfigCheckBoxWithSwatchTemplate",
          "GlobalChat"
        )
      end
      return
    end

    local parent = ChatConfigChatSettings
    local panel = CreateFrame("Frame", "iChatGlobalChatSettings", parent)
    panel:SetSize(200, 10)
    -- Sit below the default left column of player message types.
    if ChatConfigChatSettingsLeft then
      panel:SetPoint("TOPLEFT", ChatConfigChatSettingsLeft, "BOTTOMLEFT", 0, -16)
    else
      panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 10)
    end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    title:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 4, 2)
    title:SetText("GlobalChat")
    panel.Title = title
    -- ChatConfig_CreateCheckboxes expects ParentName.."Title"
    _G[panel:GetName() .. "Title"] = title

    if ChatConfig_CreateCheckboxes then
      local template = "ChatConfigCheckBoxWithSwatchTemplate"
      if not _G[template] then
        template = "ChatConfigCheckBoxWithSwatchAndClassColorTemplate"
      end
      local ok, err = pcall(ChatConfig_CreateCheckboxes, panel, ICHAT_CONFIG_GLOBALCHAT, template, "GlobalChat")
      if not ok then
        print("|cffd4a017iChat|r ChatConfig panel note: " .. tostring(err))
      end
    end
  end

  -- Build after Blizzard creates its checkboxes (PLAYER_ENTERING_WORLD on ChatConfigFrame).
  if ChatConfigFrame then
    ChatConfigFrame:HookScript("OnEvent", function(_, event)
      if event == "PLAYER_ENTERING_WORLD" then
        buildPanel()
      end
    end)
    ChatConfigFrame:HookScript("OnShow", function()
      buildPanel()
      if ChatConfig_UpdateCheckboxes and _G.iChatGlobalChatSettings then
        ChatConfig_UpdateCheckboxes(_G.iChatGlobalChatSettings)
      end
    end)
  end

  -- Also append into CHAT_CONFIG_CHAT_LEFT so types exist if our panel template is missing.
  if type(CHAT_CONFIG_CHAT_LEFT) == "table" then
    for _, def in ipairs(C.LIST) do
      local exists
      for _, row in ipairs(CHAT_CONFIG_CHAT_LEFT) do
        if row.type == def.key then
          exists = true
          break
        end
      end
      if not exists then
        table.insert(CHAT_CONFIG_CHAT_LEFT, makeConfigEntry(def))
      end
    end
  end
end

------------------------------------------------------------------------
-- Display inbound messages in enabled ChatFrames
------------------------------------------------------------------------

function C.PaintMessage(msg)
  ensureChatDB()
  local kind = msg.channel or msg.kind or "say"
  local def = C.BY_KIND[kind] or C.BY_KEY[msg.chatType] or C.BY_KIND.say
  local key = def.key
  local info = ChatTypeInfo[key] or { r = def.r, g = def.g, b = def.b }
  local body
  if kind == "whisper" then
    local target = msg.target or ""
    body = string.format("[%s] %s to %s: %s", def.label, msg.sender or "?", target, msg.text or "")
  elseif kind == "room" then
    body = string.format("[%s:%s] %s: %s", def.label, msg.roomName or msg.room or "?", msg.sender or "?", msg.text or "")
  else
    body = string.format("[%s] %s: %s", def.label, msg.sender or "?", msg.text or "")
  end

  local num = NUM_CHAT_WINDOWS or 10
  local any = false
  for i = 1, num do
    if listeningOn(key, i) then
      local frame = _G["ChatFrame" .. i]
      if frame then
        frame:AddMessage(body, info.r, info.g, info.b, info.id)
        any = true
      end
    end
  end
  if not any and DEFAULT_CHAT_FRAME then
    -- Fallback so players still see traffic before enabling checkboxes.
    DEFAULT_CHAT_FRAME:AddMessage(body, info.r, info.g, info.b, info.id)
  end
end

------------------------------------------------------------------------
-- Slash commands → outbox
------------------------------------------------------------------------

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sendKind(kind, raw)
  raw = trim(raw)
  if raw == "" then
    local def = C.BY_KIND[kind]
    print("|cffd4a017iChat|r usage: /" .. (def and def.slash[1] or kind) .. " <message>")
    return
  end

  if kind == "whisper" then
    local target, text = raw:match("^(%S+)%s+(.+)$")
    if not target or not text then
      print("|cffd4a017iChat|r usage: /gwhisper Player-Realm message")
      return
    end
    IChat.SendChannel("whisper", text, { target = target })
    return
  end

  if kind == "room" then
    -- "/groom name message" OR "/groom message" using saved room
    local maybeName, rest = raw:match("^(%S+)%s+(.+)$")
    if maybeName and rest and not IChat.LooksLikeMessageOnly(maybeName, rest) then
      IChat.SetRoomName(maybeName)
      IChat.SendChannel("room", rest, { roomName = maybeName })
      return
    end
    IChat.SendChannel("room", raw, { roomName = IChat.GetRoomName() })
    return
  end

  IChat.SendChannel(kind, raw)
end

-- Heuristic: if first token looks like a room name (no spaces already) and second exists,
-- treat as room+message. Always true when two tokens present — documented in help.
function IChat.LooksLikeMessageOnly(_first, _rest)
  return false
end

function C.RegisterSlashCommands()
  for _, def in ipairs(C.LIST) do
    local kind = def.kind
    local slashName = "ICHAT" .. string.upper(kind)
    for i, cmd in ipairs(def.slash) do
      _G["SLASH_" .. slashName .. i] = "/" .. cmd
    end
    SlashCmdList[slashName] = function(msg)
      sendKind(kind, msg)
    end
  end
end

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name ~= "iChat" then
    return
  end
  C.RegisterTypes()
  C.HookPersistence()
  C.RegisterSlashCommands()
  if event == "PLAYER_LOGIN" then
    C.InstallChatConfigSection()
    C.ApplyToChatFrames()
    print("|cffd4a017iChat|r GlobalChat ready — Chat settings → GlobalChat; /gsay /gtrade /gcity /groom /gwhisper; /ichat sync")
  end
end)
