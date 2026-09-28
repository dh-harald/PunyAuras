-- The Trigger tab: how the triggers combine, one section per trigger, and
-- "Add Trigger" (WeakAuras TriggerOptions.lua and BuffTrigger2.lua options,
-- GPLv2). The trigger types: the aura trigger, and WeakAuras' generic
-- triggers (Prototypes.lua) of the "spell", "item" and "unit" types, each
-- with the events of TRIGGER_EVENTS. The weapon enchant, health and power
-- options are built here, the other events' in
-- Options/GenericTriggerOptions.lua.
--
-- The aura filters are the ones the 1.12.1 aura API can answer:
--   * UnitBuff / UnitDebuff give an aura's icon and stack count, and a
--     debuff's dispel type; the optional raid filter narrows debuffs to
--     the ones the player can dispel. "Only Castable by Me" takes the
--     buffs the raid filter lists (castable on others) and the ones named
--     like a spell in the player's or the pet's spellbook, since the raid
--     filter leaves out self-only buffs such as Lightning Shield. There is
--     no caster, so "own auras only" cannot be filtered.
--   * Names come from the aura's tooltip.
--   * Remaining time exists only for the player's own auras
--     (GetPlayerBuffTimeLeft), so that filter is offered for the player
--     unit alone.
--
-- The weapon enchant trigger watches the main or the off hand (the 1.12.1
-- client reports no ranged enchant); its name filter matches the enchant's
-- name with or without the rank ("Rockbiter 2" or "Rockbiter").
--
-- Of WeakAuras' "unit" triggers (Player/Unit Info) there are Health and
-- Power. Health is a percent for a unit outside the player's group, and
-- power is only a unit's primary power (Core/Triggers.lua, "Unit values").

local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

local TRIGGER_TYPES = {
	aura2 = L["Aura"],
	spell = L["Spell"],
	item = L["Item"],
	unit = L["Player/Unit Info"],
}

-- The events of WeakAuras' generic trigger types that exist here, under
-- WeakAuras' names, and each type's first event. The events beyond the
-- weapon enchant, health and power are Core/GenericTriggers.lua's, their
-- options Options/GenericTriggerOptions.lua's.
local TRIGGER_EVENTS = {
	spell = {
		["Cooldown Progress (Spell)"] = L["Cooldown/Charges/Count"],
		["Global Cooldown"] = L["Global Cooldown"],
		["Spell Known"] = L["Spell Known"],
	},
	item = {
		["Weapon Enchant"] = L["Weapon Enchant"],
		["Cooldown Progress (Equipment Slot)"] = L["Cooldown Progress (Slot)"],
		["Cooldown Progress (Item)"] = L["Cooldown Progress (Item)"],
		["Item Equipped"] = L["Item Equipped"],
		["Item Count"] = L["Item Count"],
	},
	unit = {
		Health = L["Health"],
		Power = L["Power"],
		Experience = L["Player Experience"],
		["Faction Reputation"] = L["Faction Reputation"],
		Money = L["Player Money"],
		["Stance/Form/Aura"] = L["Stance/Form/Aura"],
		["Talent Known"] = L["Talent Known"],
		Location = L["Location"],
		["Pet Behavior"] = L["Pet"],
		Conditions = L["Conditions"],
	},
}
local FIRST_EVENTS = {
	spell = "Cooldown Progress (Spell)",
	item = "Weapon Enchant",
	unit = "Health",
}
-- The event select's name per type.
local EVENT_LABELS = {
	spell = L["Spell Type"],
	item = L["Item Type"],
	unit = L["Info Type"],
}

-- WeakAuras' power_types as far as the 1.12.1 client has them.
local POWER_TYPES = {
	[0] = L["Mana"],
	[1] = L["Rage"],
	[2] = L["Focus"],
	[3] = L["Energy"],
	[4] = L["Combo Points"],
}

-- WeakAuras' weapon_types, less the ranged slot.
local WEAPON_TYPES = {
	main = L["Main Hand"],
	off = L["Off Hand"],
}

-- WeakAuras' weapon_enchant_types.
local WEAPON_ENCHANT_SHOW_ON = {
	showOnActive = L["Enchant Found"],
	showOnMissing = L["Enchant Missing"],
	showAlways = L["Always"],
}

-- WeakAuras' unit_types_bufftrigger_2, less the units 1.12.1 does not have
-- (focus, boss, arena, nameplates, soft targets).
local UNIT_TYPES = {
	player = L["Player"],
	target = L["Target"],
	pet = L["Pet"],
	party = L["Party"],
	raid = L["Raid"],
	group = L["Smart Group"],
	member = L["Specific Unit"],
}

local AURA_TYPES = {
	HELPFUL = L["Buff"],
	HARMFUL = L["Debuff"],
}

-- The dispel types UnitDebuff reports, lowercased as WeakAuras keys them.
local DEBUFF_CLASSES = {
	magic = L["Magic"],
	curse = L["Curse"],
	disease = L["Disease"],
	poison = L["Poison"],
	none = L["None"],
}

local OPERATORS = {
	["=="] = "=",
	["~="] = "!=",
	[">"] = ">",
	["<"] = "<",
	[">="] = ">=",
	["<="] = "<=",
}
-- Shared with the Load tab (Options/LoadOptions.lua).
PA.operatorTypes = OPERATORS

local SHOW_ON = {
	showOnActive = L["Aura(s) Found"],
	showOnMissing = L["Aura(s) Missing"],
	showAlways = L["Always"],
}

local function Trim(text)
	text = string.gsub(text or "", "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return text
end

-- A number field is stored as typed (like WeakAuras), but only when it is a
-- number or empty.
local function NumberSetter(trigger, key, onChange)
	return function(info, value)
		value = Trim(value)
		if value ~= "" and not tonumber(value) then return end
		trigger[key] = value
		if onChange then onChange() end
	end
end

-- The aura names, one input per name plus an empty one below them for the
-- next, like WeakAuras' name list (BuffTrigger2 CreateNameOptions). A name
-- is committed with Enter or when the box loses the focus; emptying a box
-- removes that name. A name added or removed changes the number of boxes,
-- so the tab is built again.
local function AddNameOptions(args, trigger, onChange, onRebuild)
	if type(trigger.auranames) ~= "table" then trigger.auranames = {} end
	local names = trigger.auranames
	local count = Compat.getn(names)

	local i
	for i = 1, count + 1 do
		local index = i
		args["auraname" .. index] = {
			type = "input",
			name = (index == 1) and L["Aura Name(s)"] or "",
			order = 11 + index / 100,
			hidden = function() return not trigger.useName end,
			get = function() return names[index] or "" end,
			set = function(info, value)
				value = Trim(value)
				local before = Compat.getn(names)
				if value == "" then
					if names[index] then table.remove(names, index) end
				else
					names[index] = value
				end
				if onChange then onChange() end
				if Compat.getn(names) ~= before then onRebuild() end
			end,
		}
	end
end

-- The options of an aura trigger, added to its section's `args`.
local function AddAuraOptions(args, trigger, onChange, onRebuild)
	local function IsHarmful() return trigger.debuffType == "HARMFUL" end

	args.unit = {
		type = "select",
		name = L["Unit"],
		order = 2,
		values = UNIT_TYPES,
	}
	args.specificUnit = {
		type = "input",
		name = L["Specific Unit"],
		desc = L["A unit id, e.g. party1, raid12, partypet2, targettarget or mouseover."],
		order = 3,
		hidden = function() return trigger.unit ~= "member" end,
	}
	args.debuffType = {
		type = "select",
		name = L["Aura Type"],
		order = 4,
		values = AURA_TYPES,
	}
	args.useName = {
		type = "toggle",
		name = L["Name(s)"],
		desc = L["Match only auras with one of these names. The name is read from the aura's tooltip."],
		order = 10,
	}
	args.useDebuffClass = {
		type = "toggle",
		name = L["Debuff Type"],
		order = 12,
		hidden = function() return not IsHarmful() end,
	}
	args.debuffClass = {
		type = "select",
		name = L["Debuff Type"],
		order = 13,
		values = DEBUFF_CLASSES,
		hidden = function() return not (IsHarmful() and trigger.useDebuffClass) end,
	}
	-- UnitBuff / UnitDebuff's raid filter.
	args.useRaidFilter = {
		type = "toggle",
		name = function()
			if IsHarmful() then return L["Only Dispellable by Me"] end
			return L["Only Castable by Me"]
		end,
		desc = function()
			if IsHarmful() then
				return L["Only debuffs you can dispel. The client does not tell who cast an aura, so this is the closest to an own-aura filter."]
			end
			return L["Only buffs of a kind you can cast: a spell of the same name in your or your pet's spellbook, or one the client lists as castable by you. The client does not tell who cast an aura, so this is the closest to an own-aura filter."]
		end,
		order = 14,
	}
	args.useStacks = {
		type = "toggle",
		name = L["Stack Count"],
		order = 20,
	}
	args.stacksOperator = {
		type = "select",
		name = L["Operator"],
		order = 21,
		values = OPERATORS,
		hidden = function() return not trigger.useStacks end,
		get = function() return trigger.stacksOperator or ">=" end,
	}
	args.stacks = {
		type = "input",
		name = L["Stack Count"],
		order = 22,
		hidden = function() return not trigger.useStacks end,
		set = NumberSetter(trigger, "stacks", onChange),
	}
	args.useRem = {
		type = "toggle",
		name = L["Remaining Time"],
		desc = L["Seconds left on the aura. The client only reports it for the player's own auras."],
		order = 23,
		hidden = function() return trigger.unit ~= "player" end,
	}
	args.remOperator = {
		type = "select",
		name = L["Operator"],
		order = 24,
		values = OPERATORS,
		hidden = function() return not (trigger.unit == "player" and trigger.useRem) end,
		get = function() return trigger.remOperator or "<=" end,
	}
	args.rem = {
		type = "input",
		name = L["Remaining Time"],
		order = 25,
		hidden = function() return not (trigger.unit == "player" and trigger.useRem) end,
		set = NumberSetter(trigger, "rem", onChange),
	}
	args.matchesShowOn = {
		type = "select",
		name = L["Show On"],
		order = 30,
		values = SHOW_ON,
		get = function() return trigger.matchesShowOn or "showOnActive" end,
	}
	AddNameOptions(args, trigger, onChange, onRebuild)
end

-- The options of a weapon enchant trigger, with WeakAuras' field names
-- (use_enchant / enchant, use_stacks / stacks / stacks_operator,
-- use_remaining / remaining / remaining_operator, showOn). The charge and
-- remaining time filters are offered only while it shows on a found
-- enchant, the only case they apply to.
local function AddWeaponEnchantOptions(args, trigger, onChange)
	local function ShowsOnActive()
		return (trigger.showOn or "showOnActive") == "showOnActive"
	end

	args.weapon = {
		type = "select",
		name = L["Weapon"],
		order = 3,
		values = WEAPON_TYPES,
		get = function() return trigger.weapon or "main" end,
	}
	args.use_enchant = {
		type = "toggle",
		name = L["Weapon Enchant"],
		desc = L["Match only this enchant. The name is read from the weapon's tooltip, e.g. \"Rockbiter 2\"; without the rank (\"Rockbiter\") it matches every rank."],
		order = 10,
	}
	args.enchant = {
		type = "input",
		name = L["Enchant Name"],
		order = 11,
		hidden = function() return not trigger.use_enchant end,
		set = function(info, value)
			trigger.enchant = Trim(value)
			if onChange then onChange() end
		end,
	}
	args.use_stacks = {
		type = "toggle",
		name = L["Stack Count"],
		desc = L["The enchant's charges. An enchant without charges has 0."],
		order = 20,
		hidden = function() return not ShowsOnActive() end,
	}
	args.stacks_operator = {
		type = "select",
		name = L["Operator"],
		order = 21,
		values = OPERATORS,
		hidden = function() return not (ShowsOnActive() and trigger.use_stacks) end,
		get = function() return trigger.stacks_operator or "<" end,
	}
	args.stacks = {
		type = "input",
		name = L["Stack Count"],
		order = 22,
		hidden = function() return not (ShowsOnActive() and trigger.use_stacks) end,
		set = NumberSetter(trigger, "stacks", onChange),
	}
	args.use_remaining = {
		type = "toggle",
		name = L["Remaining Time"],
		desc = L["Seconds left on the enchant."],
		order = 23,
		hidden = function() return not ShowsOnActive() end,
	}
	args.remaining_operator = {
		type = "select",
		name = L["Operator"],
		order = 24,
		values = OPERATORS,
		hidden = function() return not (ShowsOnActive() and trigger.use_remaining) end,
		get = function() return trigger.remaining_operator or "<" end,
	}
	args.remaining = {
		type = "input",
		name = L["Remaining Time"],
		order = 25,
		hidden = function() return not (ShowsOnActive() and trigger.use_remaining) end,
		set = NumberSetter(trigger, "remaining", onChange),
	}
	args.showOn = {
		type = "select",
		name = L["Show On"],
		order = 30,
		values = WEAPON_ENCHANT_SHOW_ON,
		get = function() return trigger.showOn or "showOnActive" end,
	}
end

-- WeakAuras' multiEntry number filters take up to two entries.
local ENTRY_LIMIT = 2

-- Entry `index` of a multiEntry field; a single value outside a list is
-- its first entry.
local function EntryValue(trigger, key, index)
	local list = trigger[key]
	if type(list) == "table" then return list[index] end
	if index == 1 then return list end
end

-- The multiEntry field `key` as a list, made one if it is not yet.
local function EntryList(trigger, key)
	local list = trigger[key]
	if type(list) ~= "table" then
		if list == nil then list = {} else list = { list } end
		trigger[key] = list
	end
	return list
end

-- A multiEntry number filter (WeakAuras' LoadOptions getValue / setValue):
-- the use_<name> toggle, then per entry an operator ("=" until one is
-- picked, as the trigger treats a missing one) and a value, kept in the
-- lists <name>_operator and <name>. The second entry is offered once the
-- first has a value; emptying an entry moves the ones after it up.
local function AddNumberFilter(args, trigger, name, label, desc, order, onChange)
	local operatorKey = name .. "_operator"
	args["use_" .. name] = {
		type = "toggle",
		name = label,
		desc = desc,
		order = order,
	}
	local entry
	for entry = 1, ENTRY_LIMIT do
		local index = entry
		local function Hidden()
			if not trigger["use_" .. name] then return true end
			return index > 1 and EntryValue(trigger, name, index - 1) == nil
		end
		args[operatorKey .. index] = {
			type = "select",
			name = L["Operator"],
			order = order + index * 0.2 - 0.1,
			values = OPERATORS,
			hidden = Hidden,
			get = function() return EntryValue(trigger, operatorKey, index) or "==" end,
			set = function(info, value)
				local list = EntryList(trigger, operatorKey)
				local i
				for i = 1, index - 1 do
					if list[i] == nil then list[i] = "==" end
				end
				list[index] = value
				if onChange then onChange() end
			end,
		}
		args[name .. index] = {
			type = "input",
			name = label,
			order = order + index * 0.2,
			hidden = Hidden,
			get = function() return EntryValue(trigger, name, index) or "" end,
			set = function(info, value)
				value = Trim(value)
				if value ~= "" and not tonumber(value) then return end
				local values = EntryList(trigger, name)
				if value == "" then
					local operators = EntryList(trigger, operatorKey)
					local i
					for i = index, ENTRY_LIMIT do
						values[i] = values[i + 1]
						operators[i] = operators[i + 1]
					end
				else
					values[index] = value
				end
				if onChange then onChange() end
			end,
		}
	end
end

-- Shared with the generic triggers' options (Options/GenericTriggerOptions.lua).
PA.AddNumberFilterOption = AddNumberFilter
PA.NumberSetter = NumberSetter

-- The options of a health or power trigger, with WeakAuras' field names
-- (unit, powertype, and the number filters of UNIT_VALUE_FIELDS in
-- Core/Triggers.lua). Another event has other filters, so changing it
-- builds the tab again.
local function AddUnitValueOptions(args, trigger, onChange)
	local isPower = trigger.event == "Power"

	args.unit = {
		type = "select",
		name = L["Unit"],
		order = 3,
		values = UNIT_TYPES,
		get = function() return trigger.unit or "player" end,
	}
	args.specificUnit = {
		type = "input",
		name = L["Specific Unit"],
		desc = L["A unit id, e.g. party1, raid12, partypet2, targettarget or mouseover."],
		order = 4,
		hidden = function() return trigger.unit ~= "member" end,
	}

	if isPower then
		local powerDesc = L["The client reports only a unit's primary power: a unit whose primary power is of another type does not match. Combo points are the player's, on the current target."]
		args.use_powertype = {
			type = "toggle",
			name = L["Power Type"],
			desc = powerDesc,
			order = 5,
		}
		args.powertype = {
			type = "select",
			name = L["Power Type"],
			order = 6,
			values = POWER_TYPES,
			hidden = function() return not trigger.use_powertype end,
			get = function() return tonumber(trigger.powertype) or 0 end,
		}
		AddNumberFilter(args, trigger, "power", L["Power"], nil, 10, onChange)
		AddNumberFilter(args, trigger, "percentpower", L["Power (%)"], nil, 20, onChange)
		AddNumberFilter(args, trigger, "deficit", L["Power Deficit"], nil, 30, onChange)
		AddNumberFilter(args, trigger, "maxpower", L["Max Power"], nil, 40, onChange)
	else
		local percentDesc = L["For a unit outside your group the client reports health as a percent, at most 100."]
		AddNumberFilter(args, trigger, "health", L["Health"], percentDesc, 10, onChange)
		AddNumberFilter(args, trigger, "percenthealth", L["Health (%)"], nil, 20, onChange)
		AddNumberFilter(args, trigger, "deficit", L["Health Deficit"], percentDesc, 30, onChange)
		AddNumberFilter(args, trigger, "maxhealth", L["Max Health"], percentDesc, 40, onChange)
	end
end

-- The fields an event needs, where missing (WeakAuras' prototype defaults).
-- A field of another event is kept: switching back finds it again.
local function SetEventDefaults(trigger)
	local event = trigger.event
	if event == "Weapon Enchant" then
		trigger.weapon = trigger.weapon or "main"
		trigger.showOn = trigger.showOn or "showOnActive"
	elseif event == "Health" or event == "Power" then
		trigger.unit = trigger.unit or "player"
	elseif event == "Cooldown Progress (Equipment Slot)" then
		trigger.itemSlot = trigger.itemSlot or 13
		trigger.genericShowOn = trigger.genericShowOn or "showOnCooldown"
	elseif event == "Cooldown Progress (Spell)" or event == "Cooldown Progress (Item)" then
		trigger.genericShowOn = trigger.genericShowOn or "showOnCooldown"
	elseif event == "Faction Reputation" then
		if trigger.use_watched == nil and not trigger.factionID then trigger.use_watched = true end
	end
end

-- Switches a trigger to another type. The fields of the type it had are
-- kept (switching back finds them again); the new type's required fields
-- get their defaults where missing, as PA:DefaultAuraTrigger and
-- WeakAuras' prototype defaults set them. The generic types share `event`,
-- which is reset when it is not one of the new type's.
local function SetTriggerType(trigger, triggerType)
	trigger.type = triggerType
	local events = TRIGGER_EVENTS[triggerType]
	if events then
		if not events[trigger.event or ""] then trigger.event = FIRST_EVENTS[triggerType] end
		SetEventDefaults(trigger)
	else
		trigger.unit = trigger.unit or "player"
		trigger.debuffType = trigger.debuffType or "HELPFUL"
		trigger.matchesShowOn = trigger.matchesShowOn or "showOnActive"
	end
end

-- The section of one trigger: its type, the options of that type, and
-- "Delete Trigger". Another type has other options, so changing the type
-- builds the tab again.
local function TriggerGroup(data, index, onChange, onRebuild)
	local trigger = data.triggers[index].trigger
	local count = Compat.getn(data.triggers)

	local args = {
		type = {
			type = "select",
			name = L["Type"],
			order = 1,
			values = TRIGGER_TYPES,
			set = function(info, value)
				if value == trigger.type then return end
				SetTriggerType(trigger, value)
				if onChange then onChange() end
				onRebuild()
			end,
		},
		deleteTrigger = {
			type = "execute",
			name = L["Delete Trigger"],
			order = 40,
			hidden = function() return count <= 1 end,
			func = function()
				table.remove(data.triggers, index)
				PA:DeleteConditionsForTrigger(data, index)
				-- An icon taken from a trigger follows it, or falls back to
				-- automatic when that trigger is the one removed.
				local source = data.iconSource or -1
				if source == index then
					data.iconSource = -1
				elseif source > index then
					data.iconSource = source - 1
				end
				if onChange then onChange() end
				onRebuild()
			end,
		},
	}
	local events = TRIGGER_EVENTS[trigger.type or ""]
	if events then
		-- Another event has other options: changing it builds the tab again.
		args.event = {
			type = "select",
			name = EVENT_LABELS[trigger.type],
			order = 2,
			values = events,
			get = function() return trigger.event end,
			set = function(info, value)
				if value == trigger.event then return end
				trigger.event = value
				SetEventDefaults(trigger)
				if onChange then onChange() end
				onRebuild()
			end,
		}
		local event = trigger.event
		if event == "Weapon Enchant" then
			AddWeaponEnchantOptions(args, trigger, onChange)
		elseif event == "Health" or event == "Power" then
			AddUnitValueOptions(args, trigger, onChange)
		else
			local builder = PA.genericTriggerOptions and PA.genericTriggerOptions[event or ""]
			if builder then builder(args, trigger, onChange, onRebuild) end
		end
	else
		AddAuraOptions(args, trigger, onChange, onRebuild)
	end

	return {
		type = "group",
		name = string.format(L["Trigger %d"], index),
		inline = true,
		order = 10 + index,
		get = function(info)
			return trigger[info[Compat.getn(info)]]
		end,
		set = function(info, value)
			trigger[info[Compat.getn(info)]] = value
			if onChange then onChange() end
		end,
		args = args,
	}
end

-- The Trigger tab of `data`. `onChange` runs after every value written;
-- `onRebuild` after a trigger was added or removed, when the tab has to be
-- built again.
function PA:GetTriggerOptions(data, onChange, onRebuild)
	local triggers = data.triggers
	local count = Compat.getn(triggers)

	local args = {
		combination = {
			type = "group",
			name = L["Trigger Combination"],
			inline = true,
			order = 1,
			args = {
				disjunctive = {
					type = "select",
					name = L["Required for Activation"],
					order = 1,
					values = function()
						if count > 1 then
							return { any = L["Any Triggers"], all = L["All Triggers"] }
						end
						return { any = string.format(L["Trigger %d"], 1) }
					end,
					get = function()
						if count > 1 then return triggers.disjunctive or "all" end
						return "any"
					end,
					set = function(info, value)
						triggers.disjunctive = value
						if onChange then onChange() end
					end,
				},
			},
		},
		addTrigger = {
			type = "execute",
			name = L["Add Trigger"],
			order = 1000,
			func = function()
				table.insert(triggers, { trigger = PA:DefaultAuraTrigger() })
				if onChange then onChange() end
				onRebuild()
			end,
		},
	}

	local i
	for i = 1, count do
		args["trigger" .. i] = TriggerGroup(data, i, onChange, onRebuild)
	end

	return {
		type = "group",
		name = L["Trigger"],
		order = 2,
		args = args,
	}
end
