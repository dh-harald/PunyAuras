-- Actions: chat messages sent when an aura shows or hides, or when one of
-- its conditions starts to hold (WeakAuras.lua PerformActions and
-- HandleChatAction, RegionPrototype.lua SendChat; GPLv2).
--
-- Data, in WeakAuras' shape:
--   data.actions = { init = {}, start = {...}, finish = {...} }
-- `start` ("On Show") and `finish` ("On Hide") hold do_message,
-- message_type, message, message_dest (a whisper's target) and r / g / b
-- (the colour of a message to the chat frame or the error frame). A
-- condition's "chat" change (Core/Conditions.lua) holds the same fields
-- but do_message.
--
-- The trigger engine hands every aura's old and new state to
-- PA:RunActions after each evaluation: "On Show" runs when the aura turns
-- active, "On Hide" when it turns inactive, with the placeholders of the
-- last active state; a condition's message when the condition starts to
-- hold. Nothing is sent while the options window is open, as in WeakAuras.
--
-- The message types are WeakAuras' send_chat_message_types that the
-- 1.12.1 client has. WeakAuras sends Say and Yell only inside an instance
-- (a later client's restriction); the 1.12.1 client has none, so they are
-- always sent.

local _G = _G or getfenv()
local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

PA.chatMessageTypes = {
	PRINT = L["Chat Frame"],
	ERROR = L["Error Frame"],
	SAY = L["Say"],
	YELL = L["Yell"],
	EMOTE = L["Emote"],
	PARTY = L["Party"],
	RAID = L["Raid"],
	RAID_WARNING = L["Raid Warning"],
	GUILD = L["Guild"],
	OFFICER = L["Officer"],
	WHISPER = L["Whisper"],
	SMARTRAID = L["BG>Raid>Party>Say"],
}

-- The message types shown in a colour of their own choosing.
PA.coloredMessageTypes = { PRINT = true, ERROR = true }

-- The battlefield queues the 1.12.1 client has (MAX_BATTLEFIELD_QUEUES).
local BATTLEFIELD_QUEUES = 3

local function Send(message, chatType, target)
	pcall(SendChatMessage, message, chatType, nil, target)
end

local function InBattleground()
	local i
	for i = 1, BATTLEFIELD_QUEUES do
		local ok, status = pcall(GetBattlefieldStatus, i)
		if ok and status == "active" then return true end
	end
	return false
end

-- WeakAuras' "BG>Raid>Party>Say": the widest group the player is in.
local function SmartChannel()
	if InBattleground() then return "BATTLEGROUND" end
	local okRaid, raid = pcall(GetNumRaidMembers)
	if okRaid and (tonumber(raid) or 0) > 0 then return "RAID" end
	local okParty, party = pcall(GetNumPartyMembers)
	if okParty and (tonumber(party) or 0) > 0 then return "PARTY" end
	return "SAY"
end

-- Sends the message `options` describe (an action's or a condition
-- change's fields), its placeholders taken from `auraState`.
function PA:SendActionMessage(options, auraState)
	if type(options) ~= "table" then return end
	local messageType, message = options.message_type, options.message
	if not (messageType and type(message) == "string" and message ~= "") then return end
	local now = GetTime()
	if string.find(message, "%", 1, true) then
		message = self:FormatText(message, auraState, now)
	end
	if message == "" then return end

	local r, g, b = tonumber(options.r) or 1, tonumber(options.g) or 1, tonumber(options.b) or 1
	if messageType == "PRINT" then
		local chat = _G.DEFAULT_CHAT_FRAME
		if chat then pcall(chat.AddMessage, chat, message, r, g, b) end
	elseif messageType == "ERROR" then
		local errors = _G.UIErrorsFrame
		if errors then pcall(errors.AddMessage, errors, message, r, g, b, 1.0) end
	elseif messageType == "WHISPER" then
		local target = options.message_dest
		if type(target) ~= "string" then return end
		if string.find(target, "%", 1, true) then
			target = self:FormatText(target, auraState, now)
		end
		if target ~= "" then Send(message, "WHISPER", target) end
	elseif messageType == "SMARTRAID" then
		Send(message, SmartChannel())
	elseif self.chatMessageTypes[messageType] then
		Send(message, messageType)
	end
end

local function Perform(data, when, auraState)
	local actions = type(data.actions) == "table" and data.actions[when]
	if type(actions) == "table" and actions.do_message then
		PA:SendActionMessage(actions, auraState)
	end
end

-- Whether `index` is in the list `list`.
local function Listed(list, index)
	if not list then return false end
	local i
	for i = 1, Compat.getn(list) do
		if list[i] == index then return true end
	end
	return false
end

-- Runs the actions of `data` for its state changing from `old` (nil
-- before the first evaluation) to `new`.
function PA:RunActions(data, old, new)
	if self.IsOptionsOpen and self:IsOptionsOpen() then return end
	local wasActive = old ~= nil and old.active
	if new.active and not wasActive then
		Perform(data, "start", new)
	elseif wasActive and not new.active then
		Perform(data, "finish", old)
	end

	local active = new.activeConditions
	if not (active and type(data.conditions) == "table") then return end
	local oldActive = old and old.activeConditions
	local i
	for i = 1, Compat.getn(active) do
		local index = active[i]
		if not Listed(oldActive, index) then
			local condition = data.conditions[index]
			local changes = condition and condition.changes
			if type(changes) == "table" then
				local c
				for c = 1, Compat.getn(changes) do
					if changes[c].property == "chat" then
						self:SendActionMessage(changes[c].value, new)
					end
				end
			end
		end
	end
end
