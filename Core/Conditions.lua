-- Conditions: region settings that change while a condition on the aura's
-- trigger states holds (WeakAuras Conditions.lua and ConditionOptions.lua,
-- the regions' `properties` and the triggers' GetTriggerConditions; GPLv2).
--
-- Data, in WeakAuras' shape:
--   data.conditions = { [n] = {
--     check = { trigger = t, variable = "stacks", op = ">=", value = 3 },
--     changes = { { property = "color", value = { 1, 0, 0, 1 } }, ... },
--     linked = bool,   -- "Else If": skipped while an earlier condition of
--   } }                -- its chain holds
-- `trigger` is a trigger number, or -1 for the global conditions (in
-- combat, has target, attackable target, always true). A check whose
-- variable is "AND" / "OR" (trigger -2) combines the checks in its
-- `checks` list; an empty combination never holds. A
-- property is a region setting ("color") or a sub-region text's
-- ("sub.2.text_color", index into data.subRegions).
--
-- Unlike WeakAuras, which compiles each aura's conditions into a function,
-- they are evaluated here: after every trigger evaluation of an active aura
-- (PA:EvaluateConditions), the indexes of the conditions that hold are
-- kept on the aura's state (`activeConditions`, `conditionKey`), and the
-- region is drawn from its data with the changes of those conditions on
-- top, the later condition winning where two change the same property
-- (PA:GetRegionData). An inactive aura has no active condition. A check on
-- a trigger's value only holds while that trigger is active; "Active"
-- (`show`) tests the trigger's activity itself. A condition on the time
-- left wakes the trigger engine when it will change.
--
-- A "chat" change is an action, not a setting: its message is sent when the
-- condition starts to hold (Core/Actions.lua). Not evaluated: WeakAuras'
-- custom checks, range checks and the other actions (sound, glow, custom
-- code); a check of an unknown variable tests nothing.

local _G = _G or getfenv()
local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

-- Trigger variables -----------------------------------------------------------

-- WeakAuras' names and types of the values a condition tests, per trigger
-- (GetTriggerConditions of BuffTrigger2.lua and GenericTrigger.lua, the
-- prototypes' conditionType arguments), as far as the trigger states here
-- carry them. Types: "bool" (value 1 / 0), "number", "timer" (an expiration
-- time, tested as the time left), "string", "select" (with `values`).

local ACTIVE = { display = L["Active"], type = "bool" }
local REMAINING = { display = L["Remaining Duration"], type = "timer" }
local TOTAL_DURATION = { display = L["Total Duration"], type = "number" }

local function Variables(list)
	list.show = ACTIVE
	return list
end

-- WeakAuras' debuff_class_types, as far as the 1.12.1 client reports them.
local DEBUFF_CLASSES = {
	magic = L["Magic"],
	curse = L["Curse"],
	disease = L["Disease"],
	poison = L["Poison"],
	none = L["None"],
}

local AURA_VARIABLES = Variables({
	debuffClass = { display = L["Debuff Type"], type = "select", values = DEBUFF_CLASSES },
	name = { display = L["Name"], type = "string" },
	stacks = { display = L["Stacks"], type = "number" },
	expirationTime = REMAINING,
	duration = TOTAL_DURATION,
})

local TIMED_VARIABLES = Variables({
	expirationTime = REMAINING,
	duration = TOTAL_DURATION,
})

local COOLDOWN_VARIABLES = Variables({
	onCooldown = { display = L["On Cooldown"], type = "bool" },
	expirationTime = REMAINING,
	duration = TOTAL_DURATION,
})

-- WeakAuras' FACTION_STANDING_LABEL1-8 values of the reputation standing.
local function StandingValues()
	local values = {}
	local i
	for i = 1, 8 do
		values[i] = _G["FACTION_STANDING_LABEL" .. i] or tostring(i)
	end
	return values
end

local EVENT_VARIABLES = {
	["Weapon Enchant"] = Variables({
		name = { display = L["Name"], type = "string" },
		stacks = { display = L["Stacks"], type = "number" },
		expirationTime = REMAINING,
		duration = TOTAL_DURATION,
	}),
	Health = Variables({
		health = { display = L["Health"], type = "number" },
		percenthealth = { display = L["Health (%)"], type = "number" },
		deficit = { display = L["Health Deficit"], type = "number" },
		maxhealth = { display = L["Max Health"], type = "number" },
	}),
	Power = Variables({
		power = { display = L["Power"], type = "number" },
		percentpower = { display = L["Power (%)"], type = "number" },
		deficit = { display = L["Power Deficit"], type = "number" },
		maxpower = { display = L["Max Power"], type = "number" },
	}),
	["Cooldown Progress (Spell)"] = COOLDOWN_VARIABLES,
	["Cooldown Progress (Equipment Slot)"] = COOLDOWN_VARIABLES,
	["Cooldown Progress (Item)"] = COOLDOWN_VARIABLES,
	["Global Cooldown"] = TIMED_VARIABLES,
	["Item Count"] = Variables({
		count = { display = L["Item Count"], type = "number" },
	}),
	Experience = Variables({
		level = { display = L["Level"], type = "number" },
		currentXP = { display = L["Current Experience"], type = "number" },
		totalXP = { display = L["Total Experience"], type = "number" },
		percentXP = { display = L["Experience (%)"], type = "number" },
		restedXP = { display = L["Rested Experience"], type = "number" },
		percentrested = { display = L["Rested Experience (%)"], type = "number" },
	}),
	["Faction Reputation"] = Variables({
		percentRep = { display = L["Reputation (%)"], type = "number" },
		standingId = { display = L["Standing"], type = "select", values = StandingValues },
	}),
	Money = Variables({
		gold = { display = L["Gold"], type = "number" },
	}),
}

local ONLY_ACTIVE = Variables({})

-- The variables a condition can test on `trigger` (a trigger's data), keyed
-- by name.
function PA:GetTriggerConditionVariables(trigger)
	if not trigger then return ONLY_ACTIVE end
	if trigger.type == "aura2" then return AURA_VARIABLES end
	return EVENT_VARIABLES[trigger.event or ""] or ONLY_ACTIVE
end

-- WeakAuras' global conditions, as far as the 1.12.1 API answers them.
local function Call(fn, a, b)
	local ok, result = pcall(fn, a, b)
	return ok and Compat.bool(result)
end

PA.globalConditions = {
	incombat = { display = L["In Combat"], type = "bool",
		read = function() return Call(UnitAffectingCombat, "player") end },
	hastarget = { display = L["Has Target"], type = "bool",
		read = function() return Call(UnitExists, "target") end },
	attackabletarget = { display = L["Attackable Target"], type = "bool",
		read = function() return Call(UnitCanAttack, "player", "target") end },
	alwaystrue = { display = L["Always True"], type = "alwaystrue" },
}

-- Region properties --------------------------------------------------------------

-- The settings a condition can change, per region type (WeakAuras'
-- `properties` of RegionTypes/*.lua and regionPrototype's alpha), as far as
-- the regions here draw them. Types: "bool", "number" (with the range of
-- its option), "color", "string", "list" (with `values`).

local ALPHA = { display = L["Alpha"], type = "number", min = 0, max = 1, step = 0.01, isPercent = true }
local WIDTH = { display = L["Width"], type = "number", min = 1, softMax = 500, max = 2000, step = 1 }
local HEIGHT = { display = L["Height"], type = "number", min = 1, softMax = 500, max = 2000, step = 1 }

local function Grouped(group, name)
	return group .. " / " .. name
end

local function StatusbarValues()
	local values = {}
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local names = LSM and LSM:List("statusbar")
	if names then
		local i
		for i = 1, Compat.getn(names) do
			values[names[i]] = names[i]
		end
	end
	return values
end

PA.regionProperties = {
	icon = {
		alpha = ALPHA,
		color = { display = L["Color"], type = "color" },
		desaturate = { display = L["Desaturate"], type = "bool" },
		width = WIDTH,
		height = HEIGHT,
		zoom = { display = L["Zoom"], type = "number", min = 0, max = 1, step = 0.01, isPercent = true },
	},
	aurabar = {
		alpha = { display = L["Bar Alpha"], type = "number", min = 0, max = 1, step = 0.01, isPercent = true },
		texture = { display = L["Bar Texture"], type = "list", values = StatusbarValues },
		barColor = { display = L["Bar Color"], type = "color" },
		backgroundColor = { display = L["Background Color"], type = "color" },
		icon = { display = Grouped(L["Icon"], L["Show Icon"]), type = "bool" },
		icon_color = { display = Grouped(L["Icon"], L["Color"]), type = "color" },
		desaturate = { display = Grouped(L["Icon"], L["Desaturate"]), type = "bool" },
		width = WIDTH,
		height = HEIGHT,
		inverse = { display = L["Inverse"], type = "bool" },
	},
	text = {
		color = { display = L["Color"], type = "color" },
		fontSize = { display = L["Font Size"], type = "number", min = 6, max = 72, step = 1 },
		displayText = { display = L["Text"], type = "string" },
	},
	texture = {
		alpha = ALPHA,
		color = { display = L["Color"], type = "color" },
		desaturate = { display = L["Desaturate"], type = "bool" },
		width = WIDTH,
		height = HEIGHT,
		mirror = { display = L["Mirror"], type = "bool" },
	},
	progresstexture = {
		alpha = ALPHA,
		foregroundColor = { display = L["Foreground Color"], type = "color" },
		backgroundColor = { display = L["Background Color"], type = "color" },
		desaturateForeground = { display = L["Desaturate Foreground"], type = "bool" },
		desaturateBackground = { display = L["Desaturate Background"], type = "bool" },
		width = WIDTH,
		height = HEIGHT,
		inverse = { display = L["Inverse"], type = "bool" },
		mirror = { display = L["Mirror"], type = "bool" },
	},
	model = {
		width = WIDTH,
		height = HEIGHT,
	},
}

local CHAT_PROPERTY = { display = L["Chat Message"], type = "chat" }

-- A sub-region text's properties (WeakAuras SubText.lua `properties`),
-- under "sub.<index>." in an aura's property list.
local SUBTEXT_PROPERTIES = {
	text_visible = { display = L["Show Text"], type = "bool" },
	text_text = { display = L["Text"], type = "string" },
	text_color = { display = L["Color"], type = "color" },
	text_fontSize = { display = L["Font Size"], type = "number", min = 6, max = 72, step = 1 },
	text_anchorXOffset = { display = L["X Offset"], type = "number", softMin = -100, softMax = 100,
		min = -2000, max = 2000, step = 1 },
	text_anchorYOffset = { display = L["Y Offset"], type = "number", softMin = -100, softMax = 100,
		min = -2000, max = 2000, step = 1 },
}

-- Every property of `data` a condition can change, keyed by its property
-- name; a sub-region text's are named "Text <n> / <setting>" (n counts the
-- texts, as their options do).
function PA:GetConditionProperties(data)
	local properties = {}
	local key, def
	for key, def in pairs(self.regionProperties[data.regionType] or {}) do
		properties[key] = def
	end
	-- WeakAuras' "Chat Message" (regionPrototype.AddProperties): an action
	-- run when the condition starts to hold (Core/Actions.lua), not a
	-- setting of the region.
	properties.chat = CHAT_PROPERTY
	if type(data.subRegions) == "table" then
		local number = 0
		local i
		for i = 1, Compat.getn(data.subRegions) do
			local sub = data.subRegions[i]
			if type(sub) == "table" and sub.type == "subtext" then
				number = number + 1
				local prefix = string.format(L["Text %d"], number)
				for key, def in pairs(SUBTEXT_PROPERTIES) do
					local copy = {}
					local k, v
					for k, v in pairs(def) do
						copy[k] = v
					end
					copy.display = Grouped(prefix, def.display)
					properties["sub." .. i .. "." .. key] = copy
				end
			end
		end
	end
	return properties
end

-- The sub-region index and the setting of a property name ("sub.2.text_color"
-- gives 2, "text_color"); nil and the name itself for a region setting.
function PA:ParseProperty(property)
	local _, _, index, key = string.find(property or "", "^sub%.(%d+)%.(.+)$")
	if index then return tonumber(index), key end
	return nil, property
end

-- The value of `property` in `data` as it is without conditions.
function PA:GetBaseProperty(data, property)
	local index, key = self:ParseProperty(property)
	if index then
		local sub = type(data.subRegions) == "table" and data.subRegions[index]
		return type(sub) == "table" and sub[key] or nil
	end
	return data[key]
end

-- Evaluation ----------------------------------------------------------------------

local function CompareNumber(value, op, target)
	if op == "==" then return value == target end
	if op == "~=" then return value ~= target end
	if op == ">" then return value > target end
	if op == "<" then return value < target end
	if op == "<=" then return value <= target end
	if op == ">=" then return value >= target end
	return false
end

-- Whether a bool check's `value` (WeakAuras' 1 / 0) matches `current`.
local function TestBool(current, value)
	local want = not (value == 0 or value == "0" or value == false)
	return (current and true or false) == want
end

-- Whether one check holds for the aura state `auraState` at `now`: true or
-- false, or nil for a check that tests nothing (not filled in, or of a
-- variable that does not exist), as WeakAuras builds no test for one. A
-- combination joins the tests of its checks, leaving out those without
-- one; a combination without any tests nothing either. A time left
-- condition hands the time it changes to `wake`.
local function TestCheck(check, triggers, auraState, now, wake)
	if type(check) ~= "table" then return nil end
	local variable = check.variable
	if variable == "AND" or variable == "OR" then
		local count, any, all = 0, false, true
		local i
		for i = 1, Compat.getn(check.checks or {}) do
			local result = TestCheck(check.checks[i], triggers, auraState, now, wake)
			if result ~= nil then
				count = count + 1
				if result then any = true else all = false end
			end
		end
		if count == 0 then return nil end
		if variable == "AND" then return all end
		return any
	end

	local triggerNum = tonumber(check.trigger)
	if not (triggerNum and variable) then return nil end
	if triggerNum == -1 then
		local global = PA.globalConditions[variable]
		if not global then return nil end
		if global.type == "alwaystrue" then return true end
		if check.value == nil then return nil end
		return TestBool(global.read(), check.value)
	end

	local data = triggers[triggerNum]
	local def = data and PA:GetTriggerConditionVariables(data.trigger)[variable]
	if not def or check.value == nil then return nil end
	local op, target = check.op, check.value
	if def.type == "number" or def.type == "timer" then
		target = tonumber(target)
		if not (target and op) then return nil end
	elseif (def.type == "string" or def.type == "select") and not op then
		return nil
	end

	local state = auraState.triggers[triggerNum]
	if not state then return false end
	if variable == "show" then return TestBool(state.active, check.value) end
	if not state.active then return false end

	local current = state[variable]
	if current == nil then return false end
	if def.type == "bool" then
		return TestBool(current, check.value)
	elseif def.type == "number" then
		local value = tonumber(current)
		if not value then return false end
		return CompareNumber(value, op, target)
	elseif def.type == "timer" then
		local expiration = tonumber(current)
		if not expiration or expiration == 0 then return false end
		if expiration - target > now then wake(expiration - target) end
		local remaining = expiration - now
		if op == "==" then return math.abs(remaining - target) < 0.05 end
		return CompareNumber(remaining, op, target)
	elseif def.type == "string" then
		local text, needle = tostring(current), tostring(check.value)
		if op == "==" then return text == needle end
		if op == "find('%s')" then return string.find(text, needle, 1, true) ~= nil end
		if op == "match('%s')" then
			local ok, found = pcall(string.find, text, needle)
			return ok and found ~= nil
		end
		return false
	elseif def.type == "select" then
		local wanted = tonumber(check.value) or check.value
		local value = tonumber(current) or current
		if op == "~=" then return value ~= wanted end
		return value == wanted
	end
	return false
end

-- The conditions of `data` that hold for its aura state `auraState`, as a
-- list of their indexes (nil for none). Only an active aura has any. A
-- condition marked `linked` is skipped while an earlier one of its chain
-- (the conditions since the last unlinked one) holds.
function PA:EvaluateConditions(data, auraState)
	local conditions = data.conditions
	if not (auraState and auraState.active and type(conditions) == "table" and conditions[1]) then
		return nil
	end
	local now = GetTime()
	local function Wake(time) PA:WakeTriggersAt(time) end
	local active = {}
	local chainHolds = false
	local i
	for i = 1, Compat.getn(conditions) do
		local condition = conditions[i]
		if not (condition.linked and i > 1) then chainHolds = false end
		local holds = TestCheck(condition.check, data.triggers, auraState, now, Wake)
		if holds == true and not chainHolds then
			table.insert(active, i)
			chainHolds = true
		end
	end
	if not active[1] then return nil end
	return active
end

-- Sets an aura state's `activeConditions` and `conditionKey` (the list as
-- text, which tells whether it changed) from `data`'s conditions.
function PA:ApplyConditions(data, auraState)
	local active = self:EvaluateConditions(data, auraState)
	auraState.activeConditions = active
	auraState.conditionKey = active and table.concat(active, ",") or nil
end

-- The data the region of `id` is drawn from: the aura's own data, or while
-- conditions hold, a copy with their changes on top (the later condition
-- winning). The copy shares every table it does not change.
function PA:GetRegionData(id)
	local data = self:GetData(id)
	local auraState = self.auraStates and self.auraStates[id]
	local active = auraState and auraState.activeConditions
	if not (data and active and type(data.conditions) == "table") then return data end

	local copy = {}
	local key, value
	for key, value in pairs(data) do
		copy[key] = value
	end
	local copiedSubs = {}
	local i
	for i = 1, Compat.getn(active) do
		local condition = data.conditions[active[i]]
		local changes = condition and condition.changes
		if type(changes) == "table" then
			local c
			for c = 1, Compat.getn(changes) do
				local change = changes[c]
				local index, setting = self:ParseProperty(change.property)
				if index then
					local sub = type(data.subRegions) == "table" and data.subRegions[index]
					if type(sub) == "table" then
						if not copiedSubs[index] then
							if copy.subRegions == data.subRegions then
								copy.subRegions = {}
								local s
								for s = 1, Compat.getn(data.subRegions) do
									copy.subRegions[s] = data.subRegions[s]
								end
							end
							local subCopy = {}
							for key, value in pairs(sub) do
								subCopy[key] = value
							end
							copy.subRegions[index] = subCopy
							copiedSubs[index] = true
						end
						copy.subRegions[index][setting] = change.value
					end
				elseif setting and setting ~= "chat" then
					copy[setting] = change.value
				end
			end
		end
	end
	return copy
end

-- Keeping references right ---------------------------------------------------------

local function FixChecksForTrigger(check, index)
	if type(check) ~= "table" then return end
	if check.trigger == index then
		check.trigger = nil
	elseif type(check.trigger) == "number" and check.trigger > index then
		check.trigger = check.trigger - 1
	end
	if type(check.checks) == "table" then
		local i
		for i = 1, Compat.getn(check.checks) do
			FixChecksForTrigger(check.checks[i], index)
		end
	end
end

-- After trigger `index` was deleted (WeakAuras' DeleteConditionsForTrigger):
-- a check on it loses its trigger, a check on a later one follows it.
function PA:DeleteConditionsForTrigger(data, index)
	if type(data.conditions) ~= "table" then return end
	local i
	for i = 1, Compat.getn(data.conditions) do
		FixChecksForTrigger(data.conditions[i].check, index)
	end
end

-- Removes sub-region `index` of `data`: a condition's change of it is
-- dropped, and a change of a later sub-region follows it.
function PA:DeleteSubRegion(data, index)
	table.remove(data.subRegions, index)
	if type(data.conditions) ~= "table" then return end
	local i
	for i = 1, Compat.getn(data.conditions) do
		local changes = data.conditions[i].changes
		if type(changes) == "table" then
			local c = 1
			while c <= Compat.getn(changes) do
				local subIndex, setting = self:ParseProperty(changes[c].property)
				if subIndex == index then
					table.remove(changes, c)
				else
					if subIndex and subIndex > index then
						changes[c].property = "sub." .. (subIndex - 1) .. "." .. setting
					end
					c = c + 1
				end
			end
		end
	end
end
