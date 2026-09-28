-- The options of the generic triggers of Core/GenericTriggers.lua, one
-- builder per event in PA.genericTriggerOptions, called by the Trigger tab
-- (Options/TriggerOptions.lua) with (args, trigger, onChange, onRebuild).
-- Names and fields follow WeakAuras' prototypes (Prototypes.lua, GPLv2);
-- the filters in the load conditions' shape use the Load tab's editors
-- (PA.conditionOptions), WeakAuras' multiEntry number filters the Trigger
-- tab's (PA.AddNumberFilterOption). Orders stay between the event select
-- (2) and "Delete Trigger" (40).

local _G = _G or getfenv()
local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

PA.genericTriggerOptions = {}

local TALENTS_PER_TAB = 20

-- WeakAuras' cooldown_progress_behavior_types.
local COOLDOWN_SHOW_ON = {
	showOnCooldown = L["On Cooldown"],
	showOnReady = L["Not on Cooldown"],
	showAlways = L["Always"],
}

-- WeakAuras' item_slot_types as the 1.12.1 client has them, the ranged slot
-- included.
local ITEM_SLOTS = {
	[1] = L["Head"],
	[2] = L["Neck"],
	[3] = L["Shoulder"],
	[5] = L["Chest"],
	[6] = L["Waist"],
	[7] = L["Legs"],
	[8] = L["Feet"],
	[9] = L["Wrist"],
	[10] = L["Hands"],
	[11] = L["Finger 1"],
	[12] = L["Finger 2"],
	[13] = L["Trinket 1"],
	[14] = L["Trinket 2"],
	[15] = L["Back"],
	[16] = L["Main Hand"],
	[17] = L["Off Hand"],
	[18] = L["Ranged"],
	[19] = L["Tabard"],
}

-- WeakAuras' pet_behavior_types of the Classic clients.
local PET_BEHAVIORS = {
	passive = L["Passive"],
	defensive = L["Defensive"],
	aggressive = L["Aggressive"],
}

local function Trim(text)
	text = string.gsub(text or "", "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return text
end

local function Changed(onChange)
	return function()
		if onChange then onChange() end
	end
end

local function Toggle(name, order, desc, hidden)
	return { type = "toggle", name = name, desc = desc, order = order, hidden = hidden }
end

-- A name input, trimmed as it is committed.
local function NameInput(trigger, key, name, desc, order, onChange)
	return {
		type = "input",
		name = name,
		desc = desc,
		order = order,
		get = function() return trigger[key] or "" end,
		set = function(info, value)
			trigger[key] = Trim(value)
			if onChange then onChange() end
		end,
	}
end

-- WeakAuras' cooldown options: "Show Global Cooldown", the remaining time
-- filter (not offered while showing when ready) and "Show".
local function AddCooldownOptions(args, trigger, onChange, order)
	local function NotOnReady()
		return trigger.genericShowOn == "showOnReady"
	end
	args.use_showgcd = Toggle(L["Show Global Cooldown"], order,
		L["A cooldown of 1.9 seconds or less is taken to be the global cooldown, and ignored unless this is on."])
	args.use_remaining = Toggle(L["Remaining Time"], order + 1, L["Seconds left on the cooldown."], NotOnReady)
	args.remaining_operator = {
		type = "select",
		name = L["Operator"],
		order = order + 2,
		values = PA.operatorTypes,
		hidden = function() return NotOnReady() or not trigger.use_remaining end,
		get = function() return trigger.remaining_operator or "<" end,
	}
	args.remaining = {
		type = "input",
		name = L["Remaining Time"],
		order = order + 3,
		hidden = function() return NotOnReady() or not trigger.use_remaining end,
		set = PA.NumberSetter(trigger, "remaining", onChange),
	}
	args.genericShowOn = {
		type = "select",
		name = L["Show"],
		order = order + 4,
		values = COOLDOWN_SHOW_ON,
		get = function() return trigger.genericShowOn or "showOnCooldown" end,
	}
end

local spellDesc = L["The name of a spell in your or your pet's spellbook; its highest rank is used."]
local itemDesc = L["The item's name, as its link shows it."]

PA.genericTriggerOptions["Cooldown Progress (Spell)"] = function(args, trigger, onChange)
	args.spellName = NameInput(trigger, "spellName", L["Spell"], spellDesc, 3, onChange)
	AddCooldownOptions(args, trigger, onChange, 10)
end

PA.genericTriggerOptions["Global Cooldown"] = function(args)
	args.use_inverse = Toggle(L["Inverse"], 3, L["Active while the global cooldown is not running."])
end

PA.genericTriggerOptions["Spell Known"] = function(args, trigger, onChange)
	args.spellName = NameInput(trigger, "spellName", L["Spell"], spellDesc, 3, onChange)
	args.use_petspell = Toggle(L["Pet Spell"], 4)
	args.use_inverse = Toggle(L["Inverse"], 5)
end

PA.genericTriggerOptions["Cooldown Progress (Equipment Slot)"] = function(args, trigger, onChange)
	args.itemSlot = {
		type = "select",
		name = L["Item Slot"],
		order = 3,
		values = ITEM_SLOTS,
		get = function() return tonumber(trigger.itemSlot) or 13 end,
	}
	AddCooldownOptions(args, trigger, onChange, 10)
end

PA.genericTriggerOptions["Cooldown Progress (Item)"] = function(args, trigger, onChange)
	args.itemName = NameInput(trigger, "itemName", L["Item"],
		L["The item's name, as its link shows it. Its cooldown is read while it is in your bags or equipped."], 3, onChange)
	AddCooldownOptions(args, trigger, onChange, 10)
end

PA.genericTriggerOptions["Item Equipped"] = function(args, trigger, onChange)
	args.itemName = NameInput(trigger, "itemName", L["Item"], itemDesc, 3, onChange)
	args.use_itemSlot = Toggle(L["Item Slot"], 4)
	args.itemSlot = {
		type = "select",
		name = L["Item Slot"],
		order = 5,
		values = ITEM_SLOTS,
		hidden = function() return not trigger.use_itemSlot end,
		get = function() return tonumber(trigger.itemSlot) or 1 end,
	}
	args.use_inverse = Toggle(L["Inverse"], 6)
end

PA.genericTriggerOptions["Item Count"] = function(args, trigger, onChange)
	args.itemName = NameInput(trigger, "itemName", L["Item"], itemDesc, 3, onChange)
	args.use_includeBank = Toggle(L["Include Bank"], 4, L["The bank counts only while it is open."])
	PA.conditionOptions.AddValueCondition(args, trigger, "count", L["Item Count"], 5, Changed(onChange),
		{ operator = true, numeric = true })
end

PA.genericTriggerOptions["Experience"] = function(args, trigger, onChange)
	local AddNumberFilter = PA.AddNumberFilterOption
	AddNumberFilter(args, trigger, "level", L["Level"], nil, 3, onChange)
	AddNumberFilter(args, trigger, "currentXP", L["Current Experience"], nil, 5, onChange)
	AddNumberFilter(args, trigger, "totalXP", L["Total Experience"], nil, 7, onChange)
	AddNumberFilter(args, trigger, "percentXP", L["Experience (%)"], nil, 9, onChange)
	AddNumberFilter(args, trigger, "restedXP", L["Rested Experience"], nil, 11, onChange)
	AddNumberFilter(args, trigger, "percentrested", L["Rested Experience (%)"], nil, 13, onChange)
end

-- The factions the reputation list shows (not the headers), by name; the
-- one the trigger names stays listed while its header is collapsed.
local function FactionValues(trigger)
	return function()
		local values = {}
		local okCount, count = pcall(GetNumFactions)
		count = okCount and tonumber(count) or 0
		local i
		for i = 1, count do
			local ok, name, _, _, _, _, _, _, _, isHeader = pcall(GetFactionInfo, i)
			if ok and name and not Compat.bool(isHeader) then values[name] = name end
		end
		if type(trigger.factionID) == "string" and trigger.factionID ~= "" then
			values[trigger.factionID] = trigger.factionID
		end
		return values
	end
end

-- The standings, FACTION_STANDING_LABEL1-8 of the client.
local function StandingValues()
	local values = {}
	local i
	for i = 1, 8 do
		values[i] = _G["FACTION_STANDING_LABEL" .. i] or tostring(i)
	end
	return values
end

PA.genericTriggerOptions["Faction Reputation"] = function(args, trigger, onChange)
	local AddNumberFilter = PA.AddNumberFilterOption
	args.use_watched = Toggle(L["Use Watched Faction"], 3)
	args.factionID = {
		type = "select",
		name = L["Faction"],
		desc = L["A faction under a collapsed header of the reputation list is not listed, and not found."],
		order = 4,
		values = FactionValues(trigger),
		hidden = function() return trigger.use_watched end,
	}
	AddNumberFilter(args, trigger, "value", L["Reputation"], nil, 6, onChange)
	AddNumberFilter(args, trigger, "total", L["Total Reputation"], nil, 8, onChange)
	AddNumberFilter(args, trigger, "percentRep", L["Reputation (%)"], nil, 10, onChange)
	args.use_standingId = Toggle(L["Standing"], 12)
	args.standingId = {
		type = "select",
		name = L["Standing"],
		order = 13,
		values = StandingValues,
		hidden = function() return not trigger.use_standingId end,
		get = function() return tonumber(trigger.standingId) end,
	}
end

PA.genericTriggerOptions["Money"] = function(args, trigger, onChange)
	PA.conditionOptions.AddValueCondition(args, trigger, "gold", L["Gold"], 3, Changed(onChange),
		{ operator = true, numeric = true })
end

-- WeakAuras' form_types: "0 - Humanoid", then the player's forms by index.
local function FormValues()
	local values = { [0] = "0 - " .. L["Humanoid"] }
	local okCount, count = pcall(GetNumShapeshiftForms)
	count = okCount and tonumber(count) or 0
	local i
	for i = 1, count do
		local ok, _, name = pcall(GetShapeshiftFormInfo, i)
		if ok and name then values[i] = i .. " - " .. name end
	end
	return values
end

PA.genericTriggerOptions["Stance/Form/Aura"] = function(args, trigger, onChange)
	PA.conditionOptions.AddMultiselect(args, trigger, "form", L["Form"], FormValues, 3, Changed(onChange))
	args.use_inverse = Toggle(L["Inverse"], 4, nil, function() return trigger.use_form == nil end)
end

-- The player's talents by WeakAuras' Classic key, "Name (Tree)".
local function TalentValues()
	local values = {}
	local perTab = MAX_NUM_TALENTS or TALENTS_PER_TAB
	local okTabs, tabs = pcall(GetNumTalentTabs)
	tabs = okTabs and tonumber(tabs) or 0
	local tab
	for tab = 1, tabs do
		local _, tabName = pcall(GetTalentTabInfo, tab)
		local okCount, count = pcall(GetNumTalents, tab)
		count = okCount and tonumber(count) or 0
		local i
		for i = 1, count do
			local ok, name = pcall(GetTalentInfo, tab, i)
			if ok and name then
				values[(tab - 1) * perTab + i] = name .. " (" .. tostring(tabName or tab) .. ")"
			end
		end
	end
	return values
end

PA.genericTriggerOptions["Talent Known"] = function(args, trigger, onChange)
	PA.conditionOptions.AddMultiselect(args, trigger, "talent", L["Talent"], TalentValues, 3, Changed(onChange))
	args.use_inverse = Toggle(L["Inverse"], 4)
end

PA.genericTriggerOptions["Location"] = function(args, trigger, onChange)
	local desc = L["Supports multiple entries, separated by commas. Escape ',' with \\. Prefix with '-' for negation."]
	PA.conditionOptions.AddValueCondition(args, trigger, "zone", L["Zone Name"], 3, Changed(onChange),
		{ multiline = true, desc = desc })
	PA.conditionOptions.AddValueCondition(args, trigger, "subzone", L["Subzone Name"], 5, Changed(onChange),
		{ multiline = true, desc = desc })
end

PA.genericTriggerOptions["Pet Behavior"] = function(args, trigger)
	args.use_behavior = Toggle(L["Pet Behavior"], 3)
	args.behavior = {
		type = "select",
		name = L["Pet Behavior"],
		order = 4,
		values = PET_BEHAVIORS,
		hidden = function() return not trigger.use_behavior end,
	}
	args.use_inverse = Toggle(L["Inverse Pet Behavior"], 5, nil, function() return not trigger.use_behavior end)
end

PA.genericTriggerOptions["Conditions"] = function(args, trigger, onChange)
	local Tristate = PA.conditionOptions.Tristate
	local changed = Changed(onChange)
	args.use_incombat = Tristate(trigger, "incombat", L["In Combat"], 3, changed)
	args.use_pvpflagged = Tristate(trigger, "pvpflagged", L["PvP Flagged"], 4, changed)
	args.use_alive = Tristate(trigger, "alive", L["Alive"], 5, changed)
	args.use_resting = Tristate(trigger, "resting", L["Resting"], 6, changed)
	args.use_HasPet = Tristate(trigger, "HasPet", L["Has Pet"], 7, changed)
	PA.conditionOptions.AddMultiselect(args, trigger, "ingroup", L["Group Type"],
		PA.conditionOptions.GROUP_TYPES, 8, changed)
end
