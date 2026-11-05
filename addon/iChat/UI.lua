--[[
  iChat UI — simple room + message frame (no Ace3 dependency for MVP).
]]

IChat = IChat or {}
IChat.UI = IChat.UI or {}

local UI = IChat.UI

local function fmtTime(ts)
  ts = tonumber(ts) or 0
  if ts > 20000000000 then
    -- milliseconds
    ts = math.floor(ts / 1000)
  end
  if date then
    return date("%H:%M:%S", ts)
  end
  return tostring(ts)
end

function UI.Create()
  if UI.frame then
    return UI.frame
  end

  local f = CreateFrame("Frame", "iChatFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 360)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  f.TitleText:SetText("iChat")

  local roomLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  roomLabel:SetPoint("TOPLEFT", 16, -32)
  roomLabel:SetText("Room")

  local roomBox = CreateFrame("EditBox", "iChatRoomBox", f, "InputBoxTemplate")
  roomBox:SetSize(160, 20)
  roomBox:SetPoint("LEFT", roomLabel, "RIGHT", 12, 0)
  roomBox:SetAutoFocus(false)
  roomBox:SetMaxLetters(64)
  roomBox:SetScript("OnEnterPressed", function(self)
    IChat.SetRoom(self:GetText())
    self:ClearFocus()
  end)
  f.roomBox = roomBox

  local joinBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  joinBtn:SetSize(70, 22)
  joinBtn:SetPoint("LEFT", roomBox, "RIGHT", 8, 0)
  joinBtn:SetText("Join")
  joinBtn:SetScript("OnClick", function()
    IChat.SetRoom(roomBox:GetText())
  end)

  local syncBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  syncBtn:SetSize(70, 22)
  syncBtn:SetPoint("LEFT", joinBtn, "RIGHT", 6, 0)
  syncBtn:SetText("Sync")
  syncBtn:SetScript("OnClick", function()
    IChat.Sync()
  end)

  local scroll = CreateFrame("ScrollFrame", "iChatScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -60)
  scroll:SetPoint("BOTTOMRIGHT", -36, 56)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(360, 1)
  scroll:SetScrollChild(content)
  f.content = content
  f.lines = {}

  local compose = CreateFrame("EditBox", "iChatComposeBox", f, "InputBoxTemplate")
  compose:SetPoint("BOTTOMLEFT", 16, 18)
  compose:SetPoint("RIGHT", f, "BOTTOMRIGHT", -100, 18)
  compose:SetHeight(24)
  compose:SetAutoFocus(false)
  compose:SetMaxLetters(500)
  compose:SetScript("OnEnterPressed", function(self)
    IChat.Send(self:GetText())
    self:SetText("")
    self:ClearFocus()
  end)
  f.compose = compose

  local sendBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sendBtn:SetSize(70, 24)
  sendBtn:SetPoint("LEFT", compose, "RIGHT", 8, 0)
  sendBtn:SetText("Send")
  sendBtn:SetScript("OnClick", function()
    IChat.Send(compose:GetText())
    compose:SetText("")
  end)

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 42)
  hint:SetPoint("RIGHT", -16, 42)
  hint:SetJustifyH("LEFT")
  hint:SetText("Companion + relay required. Sync flushes outbox / loads inbox.")

  UI.frame = f
  return f
end

function UI.Refresh()
  IChat.EnsureDB()
  local f = UI.Create()
  f.roomBox:SetText(IChatDB.room or "global")

  for _, line in ipairs(f.lines) do
    line:Hide()
  end

  local y = -2
  local room = (IChatDB.room or "global"):lower()
  local idx = 0

  local filtered = {}
  for _, m in ipairs(IChatDB.messages) do
    if not m.room or m.room:lower() == room or room == "*" then
      table.insert(filtered, m)
    end
  end
  -- keep last 40
  local start = math.max(1, #filtered - 39)
  for i = start, #filtered do
    idx = idx + 1
    local m = filtered[i]
    local line = f.lines[idx]
    if not line then
      line = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      line:SetJustifyH("LEFT")
      line:SetWidth(350)
      line:SetWordWrap(true)
      f.lines[idx] = line
    end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 4, y)
    local meta = string.format("[%s] %s · #%s", fmtTime(m.ts), m.sender or "?", m.room or "?")
    line:SetText("|cffaaaaaa" .. meta .. "|r\n" .. (m.text or ""))
    line:Show()
    y = y - (line:GetStringHeight() + 8)
  end
  f.content:SetHeight(math.max(1, -y + 8))
end

function UI.Toggle()
  local f = UI.Create()
  if f:IsShown() then
    f:Hide()
  else
    UI.Refresh()
    f:Show()
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  UI.Create()
  UI.Refresh()
end)
