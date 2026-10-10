-- Custom Lua code of an aura (WeakAuras AuraEnvironment.lua, GPLv2). The one
-- kind run here is the custom trigger combination: with
-- `triggers.disjunctive = "custom"`, the aura is active while the function
-- in `triggers.customTriggerLogic` returns a true value, called with the
-- list of the triggers' activity (true / false by trigger number), e.g.
--   function(t) return (t[1] or t[2]) and not t[3] end
--
-- As in WeakAuras, the code is compiled as "return " .. code and run in a
-- sandbox: a table standing in for the globals, whose reads fall through to
-- the real globals except for the functions and tables that would let the
-- code leave the sandbox or do harm (a blocked function reads as one that
-- does nothing, a blocked table as an empty table, and the aura gets a chat
-- warning), and whose writes stay in the sandbox. There is no `aura_env`.
-- Compiled functions are cached by their code.
--
-- A syntax error leaves the function out (the options show the message);
-- an error while it runs is printed to the chat once per aura and message,
-- and the combination counts as false. While the options window is open
-- every combination is "any", as in WeakAuras (evaluateTriggerStateTriggers).

local _G = _G or getfenv()
local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

-- WeakAuras' blockedFunctions, plus the 1.12.1 client's setglobal, which
-- writes the real globals.
local BLOCKED_FUNCTIONS = {
	getfenv = true,
	setfenv = true,
	loadstring = true,
	pcall = true,
	xpcall = true,
	setglobal = true,
	SendMail = true,
	SetTradeMoney = true,
	AddTradeMoney = true,
	PickupTradeMoney = true,
	PickupPlayerMoney = true,
	TradeFrame = true,
	MailFrame = true,
	EnumerateFrames = true,
	RunScript = true,
	AcceptTrade = true,
	SetSendMailMoney = true,
	EditMacro = true,
	DevTools_DumpCommand = true,
	hash_SlashCmdList = true,
	RegisterNewSlashCommand = true,
	CreateMacro = true,
	SetBindingMacro = true,
	GuildDisband = true,
	GuildUninvite = true,
	securecall = true,
	DeleteCursorItem = true,
	ChatEdit_SendText = true,
	ChatEdit_ActivateChat = true,
	ChatEdit_ParseText = true,
	ChatEdit_OnEnterPressed = true,
	GetButtonMetatable = true,
	GetEditBoxMetatable = true,
	GetFontStringMetatable = true,
	GetFrameMetatable = true,
}

-- WeakAuras' blockedTables, with PunyAuras' saved variables in place of
-- WeakAuras'.
local BLOCKED_TABLES = {
	SlashCmdList = true,
	SendMailMailButton = true,
	SendMailMoneyGold = true,
	MailFrameTab2 = true,
	DEFAULT_CHAT_FRAME = true,
	ChatFrame1 = true,
	PunyAurasDB = true,
	ItemRackUser = true,
	ItemRackEvents = true,
}

-- The aura whose code is running, for the warnings.
local currentId
-- Warnings and errors already printed, by aura and text.
local reported = {}

local function Report(id, message)
	local key = tostring(id) .. "\n" .. message
	if reported[key] then return end
	reported[key] = true
	DEFAULT_CHAT_FRAME:AddMessage("|cffff4040PunyAuras|r: " .. string.format(L["Error in Aura '%s'"],
		tostring(id)) .. ": " .. message)
end

local function Noop() end

local sandbox
local function SandboxGetGlobal(key)
	return sandbox[key]
end

sandbox = setmetatable({}, {
	__index = function(t, key)
		if key == "_G" then
			return t
		elseif key == "getglobal" then
			return SandboxGetGlobal
		elseif BLOCKED_FUNCTIONS[key] then
			Report(currentId, string.format(L["Forbidden function or table: %s"], tostring(key)))
			return Noop
		elseif BLOCKED_TABLES[key] then
			Report(currentId, string.format(L["Forbidden function or table: %s"], tostring(key)))
			return {}
		end
		return _G[key]
	end,
	__newindex = function(t, key, value)
		rawset(t, key, value)
	end,
	__metatable = false,
})

-- Compiled functions by their code; weak, so code no aura uses any more is
-- collected.
local cache = setmetatable({}, { __mode = "v" })

-- The function `code` of aura `id` evaluates to ("return " .. code, run in
-- the sandbox), or nil and the error message.
function PA:LoadCustomFunction(code, id)
	if type(code) ~= "string" then return nil, L["No code"] end
	local chunk = "return " .. code
	local cached = cache[chunk]
	if cached then return cached end
	local loaded, err = loadstring(chunk, "PunyAuras custom code")
	if not loaded then return nil, tostring(err) end
	setfenv(loaded, sandbox)
	currentId = id
	local ok, result = pcall(loaded)
	currentId = nil
	if not ok then return nil, tostring(result) end
	if type(result) ~= "function" then
		return nil, L["The code does not evaluate to a function."]
	end
	cache[chunk] = result
	return result
end

-- The syntax error of an aura's trigger combination code, or nil when it
-- compiles to a function (or there is no code yet).
function PA:TriggerLogicError(data)
	local code = data.triggers and data.triggers.customTriggerLogic
	if type(code) ~= "string" or string.gsub(code, "%s+", "") == "" then return nil end
	local _, err = self:LoadCustomFunction(code, data.id)
	return err
end

-- Whether an aura is active by its triggers' activity (`actives`, true /
-- false by trigger number): "all" of them, "any" of them, or what its
-- custom combination returns. While the options window is open, "any".
function PA:CombineTriggers(data, actives)
	local triggers = data.triggers
	local count = Compat.getn(triggers)
	if count == 0 then return false end
	local any, all = false, true
	local i
	for i = 1, count do
		if actives[i] then any = true else all = false end
	end
	if self.IsOptionsOpen and self:IsOptionsOpen() then return any end
	if triggers.disjunctive == "all" then return all end
	if triggers.disjunctive ~= "custom" then return any end

	local code = triggers.customTriggerLogic
	if type(code) ~= "string" or string.gsub(code, "%s+", "") == "" then return false end
	local func, err = self:LoadCustomFunction(code, data.id)
	if not func then
		Report(data.id, L["Custom Trigger Combination"] .. ": " .. tostring(err))
		return false
	end
	local list = {}
	for i = 1, count do
		list[i] = actives[i] and true or false
	end
	currentId = data.id
	local ok, result = pcall(func, list)
	currentId = nil
	if not ok then
		Report(data.id, L["Custom Trigger Combination"] .. ": " .. tostring(result))
		return false
	end
	return result and true or false
end

-- The custom code of `data` that PunyAuras would run, for the import's
-- warning (WeakAuras' scamCheck): { { name = ..., code = ... }, ... }
-- appended to `list`.
function PA:FindCustomCode(data, list)
	list = list or {}
	local triggers = type(data) == "table" and data.triggers
	if type(triggers) == "table" and triggers.disjunctive == "custom"
		and type(triggers.customTriggerLogic) == "string" then
		table.insert(list, { name = string.format(L["%s - Trigger Logic"], tostring(data.id)),
			code = triggers.customTriggerLogic })
	end
	return list
end
