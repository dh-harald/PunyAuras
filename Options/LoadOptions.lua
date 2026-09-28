-- The Load tab: the load conditions of an aura (Core/Load.lua), built the
-- way WeakAuras' LoadOptions.lua builds its options from load_prototype
-- (GPLv2).
--
-- Three-state conditions use WeakAuras' plain-toggle cycle rather than an
-- AceConfig tristate: `get` returns false (ignored), "true" or "false" -- a
-- string, so the box shows checked -- and each click moves on to the next
-- state (ignored -> true -> false -> ignored). The name shows the state:
-- plain, green for true, red with "Not" for false. A multiselect condition
-- cycles the same way through ignored, single (a dropdown) and multiple (a
-- checkbox per value).

local PA, L = unpack(PunyAuras)

-- The classes of the 1.12.1 client, keyed by UnitClass's token.
local CLASS_TYPES = {
	WARRIOR = L["Warrior"],
	PALADIN = L["Paladin"],
	HUNTER = L["Hunter"],
	ROGUE = L["Rogue"],
	PRIEST = L["Priest"],
	SHAMAN = L["Shaman"],
	MAGE = L["Mage"],
	WARLOCK = L["Warlock"],
	DRUID = L["Druid"],
}

-- WeakAuras' group_types.
local GROUP_TYPES = {
	solo = L["Not in Group"],
	group = L["In Party"],
	raid = L["In Raid"],
}

local function Trim(text)
	text = string.gsub(text or "", "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return text
end

-- The next state of the three-state cycle, from the box's new value.
local function NextState(current, checked)
	if checked then return true end
	if current == false then return nil end
	return false
end

local function StateGet(load, name)
	return function()
		local value = load["use_" .. name]
		if value == nil then return false end
		if value == false then return "false" end
		return "true"
	end
end

local function Header(name, order)
	return { type = "header", name = name, order = order }
end

-- A tristate condition (WeakAuras' "tristate").
local function Tristate(load, name, display, order, onChange)
	return {
		type = "toggle",
		name = function()
			local value = load["use_" .. name]
			if value == nil then return display end
			if value == false then return "|cFFFF0000 " .. L["Negator"] .. " " .. display .. "|r" end
			return "|cFF00FF00" .. display .. "|r"
		end,
		order = order,
		get = StateGet(load, name),
		set = function(info, checked)
			load["use_" .. name] = NextState(load["use_" .. name], checked)
			onChange()
		end,
	}
end

-- A multiselect condition: the three-state toggle, the dropdown of the
-- single state and the checkboxes of the multiple state. Switching to
-- multiple starts it from the single pick, as WeakAuras does.
local function AddMultiselect(args, load, name, display, values, order, onChange)
	local function Value()
		if type(load[name]) ~= "table" then load[name] = {} end
		return load[name]
	end

	args["use_" .. name] = {
		type = "toggle",
		name = display,
		order = order,
		desc = function()
			local value = load["use_" .. name]
			if value == true then return L["Multiselect single tooltip"] end
			if value == false then return L["Multiselect multiple tooltip"] end
			return L["Multiselect ignored tooltip"]
		end,
		get = StateGet(load, name),
		set = function(info, checked)
			local state = NextState(load["use_" .. name], checked)
			load["use_" .. name] = state
			if state == false then
				local value = Value()
				value.multi = value.multi or {}
				if value.single then value.multi[value.single] = true end
			end
			onChange()
		end,
	}
	args[name] = {
		type = "select",
		name = display,
		order = order + 0.1,
		values = values,
		hidden = function() return load["use_" .. name] ~= true end,
		get = function() return type(load[name]) == "table" and load[name].single or nil end,
		set = function(info, value)
			Value().single = value
			onChange()
		end,
	}
	args["multiselect_" .. name] = {
		type = "multiselect",
		name = display,
		order = order + 0.2,
		values = values,
		hidden = function() return load["use_" .. name] ~= false end,
		get = function(info, key)
			local value = load[name]
			return type(value) == "table" and type(value.multi) == "table" and value.multi[key] or false
		end,
		set = function(info, key, checked)
			local value = Value()
			value.multi = value.multi or {}
			value.multi[key] = checked and true or nil
			onChange()
		end,
	}
end

-- A condition with a value of its own: the toggle, then the value's input
-- while it is on. `numeric` accepts only a number (or nothing).
local function AddValueCondition(args, load, name, display, order, onChange, options)
	options = options or {}
	args["use_" .. name] = {
		type = "toggle",
		name = display,
		order = order,
		get = function() return load["use_" .. name] end,
		set = function(info, value)
			load["use_" .. name] = value
			onChange()
		end,
	}
	if options.operator then
		args[name .. "_operator"] = {
			type = "select",
			name = L["Operator"],
			order = order + 0.1,
			values = PA.operatorTypes,
			hidden = function() return not load["use_" .. name] end,
			get = function() return load[name .. "_operator"] or "==" end,
			set = function(info, value)
				load[name .. "_operator"] = value
				onChange()
			end,
		}
	end
	args[name] = {
		type = "input",
		name = display,
		desc = options.desc,
		multiline = options.multiline,
		order = order + 0.2,
		hidden = function() return not load["use_" .. name] end,
		get = function() return load[name] and tostring(load[name]) or "" end,
		set = function(info, value)
			if not options.multiline then value = Trim(value) end
			if options.numeric and value ~= "" and not tonumber(value) then return end
			load[name] = value
			onChange()
		end,
	}
end

-- Shared with the generic triggers' options (Options/GenericTriggerOptions.lua),
-- whose filters have the load conditions' shape; `load` is then the trigger.
PA.conditionOptions = {
	Tristate = Tristate,
	AddMultiselect = AddMultiselect,
	AddValueCondition = AddValueCondition,
	GROUP_TYPES = GROUP_TYPES,
}

-- The Load tab of `data`. `onChange` runs after every value written.
function PA:GetLoadOptions(data, onChange)
	local load = data.load
	local function Changed()
		if onChange then onChange() end
	end

	local args = {
		generalTitle = Header(L["General"], 1),
		use_combat = Tristate(load, "combat", L["In Combat"], 2, Changed),
		use_never = {
			type = "toggle",
			name = L["Never"],
			order = 3,
			get = function() return load.use_never end,
			set = function(info, value)
				load.use_never = value
				Changed()
			end,
		},
		use_alive = Tristate(load, "alive", L["Alive"], 4, Changed),
		playerTitle = Header(L["Player"], 10),
		locationTitle = Header(L["Location"], 30),
	}
	AddMultiselect(args, load, "class", L["Player Class"], CLASS_TYPES, 11, Changed)
	AddValueCondition(args, load, "spellknown", L["Spell Known"], 12, Changed, {
		desc = L["The name of a spell in your or your pet's spellbook."],
	})
	AddValueCondition(args, load, "level", L["Player Level"], 13, Changed, {
		operator = true,
		numeric = true,
	})
	AddMultiselect(args, load, "ingroup", L["Group Type"], GROUP_TYPES, 14, Changed)
	AddValueCondition(args, load, "zone", L["Zone Name"], 31, Changed, {
		multiline = true,
		desc = L["Supports multiple entries, separated by commas. Escape ',' with \\. Prefix with '-' for negation."],
	})

	return {
		type = "group",
		name = L["Load"],
		order = 3,
		args = args,
	}
end
