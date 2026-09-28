-- Load conditions: whether an aura is loaded at all (WeakAuras'
-- load_prototype in Prototypes.lua and ScanForLoads in WeakAuras.lua, GPLv2).
--
-- data.load holds the conditions in WeakAuras' shape, use_<name> plus the
-- condition's own fields:
--   * toggle (never): applies while use_ is true.
--   * tristate (combat, alive): use_ true requires the state, false its
--     absence, nil ignores it.
--   * multiselect (class, ingroup): use_ true matches <name>.single, false
--     any key set in <name>.multi, nil ignores it.
--   * number (level): compared with <name>_operator, "==" by default.
--   * string (zone): WeakAuras' comma list. An entry matches exactly, a "-"
--     in front negates it, "\" escapes the next character.
--   * spell (spellknown): a spell name, looked up case-insensitively in the
--     player's and the pet's spellbook. The 1.12.1 client has no spell ids.
--
-- PA.loaded[id] follows WeakAuras' Private.loaded: true when every condition
-- holds; false ("standby") when only optional conditions fail -- the ones
-- that change in play (combat, alive, group, zone); nil otherwise. Only a
-- loaded aura's triggers are evaluated (Core/Triggers.lua).

local PA = unpack(PunyAuras)
local Compat = PunyAuras.Compat

PA.loaded = {}

local function Trim(text)
	text = string.gsub(text or "", "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return text
end

local function Compare(value, operator, target)
	value = tonumber(value) or 0
	if operator == "~=" then return value ~= target end
	if operator == ">" then return value > target end
	if operator == "<" then return value < target end
	if operator == ">=" then return value >= target end
	if operator == "<=" then return value <= target end
	return value == target
end

-- Spellbook ----------------------------------------------------------------------

-- [lowercased name] = { index, book } for every spell in the player's and
-- the pet's spellbook, built on first use after InvalidateKnownSpells. The
-- book lists a spell's ranks in order, so the index kept is the highest
-- rank's; a spell in both books is the player's.
local knownSpells

function PA:InvalidateKnownSpells()
	knownSpells = nil
end

local function AddBook(spells, bookType)
	local i = 1
	while true do
		local ok, name = pcall(GetSpellName, i, bookType)
		if not ok or not name then break end
		local key = string.lower(name)
		local known = spells[key]
		if not known or known.book == bookType then
			spells[key] = { index = i, book = bookType }
		end
		i = i + 1
	end
end

local function KnownSpells()
	if not knownSpells then
		knownSpells = {}
		AddBook(knownSpells, "spell")
		AddBook(knownSpells, "pet")
	end
	return knownSpells
end

-- Whether `name` is a spell in the player's or the pet's spellbook.
function PA:KnowsSpell(name)
	return name ~= nil and KnownSpells()[string.lower(name)] ~= nil
end

-- The spellbook index and book ("spell" or "pet") of spell `name`, its
-- highest rank; nil for a spell not in either book.
function PA:FindSpell(name)
	if type(name) ~= "string" then return nil end
	local known = KnownSpells()[string.lower(name)]
	if known then return known.index, known.book end
end

-- Zone lists --------------------------------------------------------------------

-- WeakAuras' Private.ExecEnv.ParseStringCheck: a check function for a comma
-- list. With both kinds of entries a value must be listed and not negated;
-- with only negated entries any value not negated passes.
local function ParseStringCheck(input)
	local entries, negative = {}, {}
	local function Add(entry, negate)
		if negate then negative[entry] = true else entries[entry] = true end
	end

	local len = string.len(input)
	local start, partial, escaped, negate = 1, "", false, false
	local i
	for i = 1, len do
		local c = string.sub(input, i, i)
		if escaped then
			escaped = false
		elseif c == "\\" then
			partial = partial .. string.sub(input, start, i - 1)
			start = i + 1
			escaped = true
		elseif c == "," then
			Add(partial .. Trim(string.sub(input, start, i - 1)), negate)
			start = i + 1
			partial = ""
			negate = false
		elseif c == "-" and Trim(partial) == "" and Trim(string.sub(input, start, i - 1)) == "" then
			start = i + 1
			negate = true
		end
	end
	Add(partial .. Trim(string.sub(input, start, len)), negate)

	local hasEntries = next(entries) ~= nil
	local hasNegative = next(negative) ~= nil
	return function(value)
		if value == nil then return false end
		if hasEntries and hasNegative then
			return (entries[value] and not negative[value]) and true or false
		elseif hasEntries then
			return entries[value] and true or false
		elseif hasNegative then
			return not negative[value]
		end
		return false
	end
end

-- Parsed lists by their text, so a list is parsed once, not per evaluation.
local stringChecks = {}

local function StringCheck(input)
	local check = stringChecks[input]
	if not check then
		check = ParseStringCheck(input)
		stringChecks[input] = check
	end
	return check
end

-- Conditions ----------------------------------------------------------------------

-- The load conditions offered, in WeakAuras' order.
local CONDITIONS = {
	{ name = "combat", type = "tristate", optional = true },
	{ name = "never", type = "toggle" },
	{ name = "alive", type = "tristate", optional = true },
	{ name = "class", type = "multiselect" },
	{ name = "spellknown", type = "spell" },
	{ name = "level", type = "number" },
	{ name = "ingroup", type = "multiselect", optional = true },
	{ name = "zone", type = "string", optional = true },
}

-- The player's state the conditions are checked against, read once per
-- scan. `ingroup` uses WeakAuras' group_types keys; the raid count is
-- checked first, as a raid member also has party members.
function PA:LoadEnvironment()
	local env = {}
	local ok, value, token

	ok, value = pcall(UnitAffectingCombat, "player")
	env.combat = ok and Compat.bool(value)
	ok, value = pcall(UnitIsDeadOrGhost, "player")
	env.alive = not (ok and Compat.bool(value))
	ok, value, token = pcall(UnitClass, "player")
	env.class = ok and token or nil
	ok, value = pcall(UnitLevel, "player")
	env.level = ok and tonumber(value) or 0

	local okRaid, raid = pcall(GetNumRaidMembers)
	local okParty, party = pcall(GetNumPartyMembers)
	if okRaid and (tonumber(raid) or 0) > 0 then
		env.ingroup = "raid"
	elseif okParty and (tonumber(party) or 0) > 0 then
		env.ingroup = "group"
	else
		env.ingroup = "solo"
	end

	ok, value = pcall(GetRealZoneText)
	env.zone = ok and value or nil
	return env
end

-- Whether one condition holds; a condition that is not in use holds.
-- `load` is any table in the load conditions' shape (a trigger's filters
-- use the same, PA:ConditionHolds).
local function Holds(condition, load, env)
	local name = condition.name
	local use = load["use_" .. name]
	local kind = condition.type

	if kind == "toggle" then
		-- "Never" is the only toggle: in use, it never holds.
		if use then return false end
	elseif kind == "tristate" then
		if use == true then return env[name] and true or false end
		if use == false then return not env[name] end
	elseif kind == "multiselect" then
		local value = load[name]
		local current = env[name]
		if use == true then
			local single = type(value) == "table" and value.single
			if single ~= nil and single ~= false then return current == single end
		elseif use == false then
			local multi = type(value) == "table" and value.multi
			if type(multi) == "table" then
				local key, picked
				for key, picked in pairs(multi) do
					if picked and key == current then return true end
				end
				return false
			end
		end
	elseif kind == "number" then
		local target = use and tonumber(load[name])
		if target then
			return Compare(env[name], load[name .. "_operator"] or "==", target)
		end
	elseif kind == "string" then
		if use and type(load[name]) == "string" then
			return StringCheck(load[name])(env[name])
		end
	elseif kind == "spell" then
		local spell = use and type(load[name]) == "string" and Trim(load[name])
		if spell and spell ~= "" then
			return KnownSpells()[string.lower(spell)] and true or false
		end
	end
	return true
end

-- Whether filter `name` of kind `kind` ("tristate", "multiselect",
-- "number", "string") in `fields` (use_<name> and the filter's own fields,
-- as in data.load) holds for `value`; a filter not in use holds.
function PA:ConditionHolds(kind, name, fields, value)
	return Holds({ name = name, type = kind }, fields, { [name] = value })
end

-- true (loaded), false (standby) or nil (not loaded) for `data`, checked
-- against `env` (PA:LoadEnvironment()).
function PA:CheckLoad(data, env)
	local load = data.load
	if type(load) ~= "table" then return true end

	local optionalFailed = false
	local i
	for i = 1, Compat.getn(CONDITIONS) do
		local condition = CONDITIONS[i]
		if not Holds(condition, load, env) then
			if not condition.optional then return nil end
			optionalFailed = true
		end
	end
	return not optionalFailed
end
