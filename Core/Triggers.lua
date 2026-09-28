-- Trigger evaluation: which auras are active, and what their triggers found
-- (the job of WeakAuras' BuffTrigger2, for the aura trigger).
--
-- Aura sources, as far as the 1.12.1 API goes:
--   * The player's own auras come from the GetPlayerBuff* family, the only
--     one that reports the time left.
--   * Any other unit's come from UnitBuff / UnitDebuff: icon, stacks and a
--     debuff's dispel type. Every slot is read (1-32 buffs, 1-16 debuffs):
--     an occupied slot can follow an empty one.
--   * Names come from the aura's tooltip, read with a hidden scan tooltip.
--
-- The weapon enchant trigger (WeakAuras' generic "item" trigger, event
-- "Weapon Enchant") reads GetWeaponEnchantInfo and the weapon's tooltip; see
-- the "Weapon enchants" section.
--
-- The health and power triggers (the generic "unit" trigger, events "Health"
-- and "Power") read UnitHealth / UnitMana; see the "Unit values" section.
-- The other generic triggers (cooldowns, items, player values and state)
-- are registered by Core/GenericTriggers.lua and evaluated here; one that
-- changes without an event (a cooldown running out) wakes the engine at
-- that time (PA:WakeTriggersAt).
--
-- Events only mark the state dirty; the evaluation runs at most every
-- EVALUATE_INTERVAL, plus every BACKSTOP_INTERVAL regardless, since the
-- Unreal Azeroth client's events are undocumented and not all of them are
-- measured.
--
-- Every evaluation first checks the load conditions (Core/Load.lua); the
-- triggers of an aura that is not loaded are not evaluated.
--
-- PA.auraStates[id] = {
--   active = bool,
--   activeConditions, conditionKey,  -- the conditions that hold
--                                    -- (Core/Conditions.lua)
--   triggers = { [n] = { active, found, icon, name, stacks, applications,
--                        timeLeft, expirationTime, unit, duration,
--                        progressType, value, total } },
-- (a weapon enchant's stacks are its charges; an aura's `applications` is
-- the client's stack count, 0 or 1 for an aura that does not stack, and its
-- name, while none was found, the name its icon stands for. A trigger may
-- carry more fields under WeakAuras' names, which conditions test (health,
-- percenthealth, onCooldown, level, ...). progressType
-- is WeakAuras' progress: "timed" with duration / expirationTime for the
-- player's own auras and weapon enchants, "static" with value / total for
-- the health and power triggers, nil for the rest.)
-- }

local _G = _G or getfenv()
local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

local EVALUATE_INTERVAL = 0.1
local BACKSTOP_INTERVAL = 1

local MAX_BUFFS, MAX_DEBUFFS = 32, 16
local SCAN_TOOLTIP = "PunyAurasScanTooltip"

PA.auraStates = {}

-- Aura names -----------------------------------------------------------------

local scanTooltip

-- The left-hand tooltip lines after `setter(...)` on the scan tooltip, as a
-- list of strings (empty when nothing was filled in). The lines are read
-- before the tooltip is hidden. The owner is set on every scan (hiding
-- drops it, and an unowned tooltip is not filled), and the tooltip is
-- always hidden again: left shown, it stays on screen as a native-looking
-- tooltip. Unreal Azeroth fills a scan tooltip only when it is built from
-- GameTooltipTemplate.
local function ScanTooltip(setter, a1, a2, a3)
	local lines = {}
	if not scanTooltip then
		local ok, tooltip = pcall(CreateFrame, "GameTooltip", SCAN_TOOLTIP, nil, "GameTooltipTemplate")
		if not ok or not tooltip then return lines end
		scanTooltip = tooltip
	end
	pcall(scanTooltip.SetOwner, scanTooltip, UIParent, "ANCHOR_NONE")
	pcall(scanTooltip.ClearLines, scanTooltip)

	if pcall(scanTooltip[setter], scanTooltip, a1, a2, a3) then
		-- The first line is read even when NumLines reports none.
		local okCount, count = pcall(scanTooltip.NumLines, scanTooltip)
		count = okCount and tonumber(count) or 1
		if count < 1 then count = 1 end
		local i
		for i = 1, count do
			local line = _G[SCAN_TOOLTIP .. "TextLeft" .. i]
			local text = line and line:GetText()
			table.insert(lines, text or "")
		end
	end
	pcall(scanTooltip.Hide, scanTooltip)
	return lines
end

-- The first tooltip line: an aura's name.
local function ScanName(setter, a1, a2, a3)
	local name = ScanTooltip(setter, a1, a2, a3)[1]
	if name == "" then name = nil end
	return name
end

-- Names by aura slot, kept across evaluations: an aura in the same slot
-- with the same icon is taken to be the same aura, so its tooltip is read
-- once rather than on every evaluation.
local slotNames = {}

local function AuraName(aura)
	if aura.name then return aura.name end
	local memo = slotNames[aura.slotKey]
	if memo and memo.icon == aura.icon then
		aura.name = memo.name
		return aura.name
	end

	local name
	if aura.buffIndex then
		name = ScanName("SetPlayerBuff", aura.buffIndex)
	elseif aura.harmful then
		name = ScanName("SetUnitDebuff", aura.unit, aura.index, aura.raidFilter)
	else
		name = ScanName("SetUnitBuff", aura.unit, aura.index, aura.raidFilter)
	end

	slotNames[aura.slotKey] = { icon = aura.icon, name = name }
	if name then PA:CacheIcon(name, aura.icon) end
	aura.name = name
	return name
end

-- Aura lists -------------------------------------------------------------------

-- Stacks as a count of applications: the client reports 0 or 1 for an aura
-- that does not stack (Unreal Azeroth's GetPlayerBuffApplications gives 1).
-- The client's own number is kept as `applications`, which a text shows
-- from 2 on, as the client's buff and debuff frames do.
local function Stacks(count)
	count = tonumber(count) or 0
	if count < 1 then return 1 end
	return count
end

-- The player's auras of one kind. With `raidFilter`, only those whose icon
-- UnitBuff / UnitDebuff also lists under the raid filter (GetPlayerBuff has
-- no such filter of its own).
local function CollectPlayerAuras(harmful, raidFilter)
	local filter = harmful and "HARMFUL" or "HELPFUL"
	local allowed
	if raidFilter then
		allowed = {}
		local unitAura = harmful and UnitDebuff or UnitBuff
		local i
		for i = 1, harmful and MAX_DEBUFFS or MAX_BUFFS do
			local ok, icon = pcall(unitAura, "player", i, 1)
			if ok and icon then allowed[icon] = true end
		end
	end

	local auras = {}
	local i = 0
	while true do
		local ok, buffIndex = pcall(GetPlayerBuff, i, filter)
		if not ok or not buffIndex or buffIndex < 0 then break end
		local okIcon, icon = pcall(GetPlayerBuffTexture, buffIndex)
		if okIcon and icon and (not allowed or allowed[icon]) then
			local okCount, count = pcall(GetPlayerBuffApplications, buffIndex)
			local okTime, timeLeft = pcall(GetPlayerBuffTimeLeft, buffIndex)
			local okClass, class = pcall(GetPlayerBuffDispelType, buffIndex)
			table.insert(auras, {
				unit = "player",
				harmful = harmful,
				buffIndex = buffIndex,
				slotKey = "player:" .. filter .. ":" .. buffIndex,
				icon = icon,
				stacks = Stacks(okCount and count),
				applications = okCount and tonumber(count) or 0,
				timeLeft = okTime and tonumber(timeLeft) or nil,
				class = okClass and class or nil,
			})
		end
		i = i + 1
	end
	return auras
end

local function CollectUnitAuras(unit, harmful, raidFilter)
	local auras = {}
	local unitAura = harmful and UnitDebuff or UnitBuff
	local filterArg = raidFilter and 1 or nil
	local i
	for i = 1, harmful and MAX_DEBUFFS or MAX_BUFFS do
		local ok, icon, count, class = pcall(unitAura, unit, i, filterArg)
		if ok and icon then
			table.insert(auras, {
				unit = unit,
				harmful = harmful,
				index = i,
				raidFilter = filterArg,
				slotKey = unit .. ":" .. (harmful and "HARMFUL" or "HELPFUL") .. ":" ..
					(raidFilter and "r" or "") .. i,
				icon = icon,
				stacks = Stacks(count),
				applications = tonumber(count) or 0,
				class = harmful and class or nil,
			})
		end
	end
	return auras
end

-- The buffs of `auras` (a unit's full buff list) the player can cast: the
-- ones UnitBuff lists under its raid filter, and the ones named like a spell
-- in the player's or the pet's spellbook. The raid filter only lists buffs
-- the player can cast on others, and leaves out self-only ones (Lightning
-- Shield, Demon Skin) on both clients.
local function CastableBuffs(unit, auras)
	local listed = {}
	local i
	for i = 1, MAX_BUFFS do
		local ok, icon = pcall(UnitBuff, unit, i, 1)
		if ok and icon then listed[icon] = true end
	end

	local castable = {}
	local a
	for a = 1, Compat.getn(auras) do
		local aura = auras[a]
		if listed[aura.icon] or PA:KnowsSpell(AuraName(aura)) then
			table.insert(castable, aura)
		end
	end
	return castable
end

-- Aura lists read during one evaluation, shared by every trigger that looks
-- at the same unit and kind.
local passAuras

local function GetAuras(unit, harmful, raidFilter)
	local key = unit .. (harmful and ":h" or ":b") .. (raidFilter and ":r" or "")
	local auras = passAuras[key]
	if not auras then
		if raidFilter and not harmful then
			auras = CastableBuffs(unit, GetAuras(unit, false, false))
		elseif unit == "player" then
			auras = CollectPlayerAuras(harmful, raidFilter)
		else
			auras = CollectUnitAuras(unit, harmful, raidFilter)
		end
		passAuras[key] = auras
	end
	return auras
end

-- Matching -------------------------------------------------------------------

local function Compare(value, operator, target)
	target = tonumber(target)
	if not target then return true end
	value = tonumber(value) or 0
	if operator == "==" then return value == target end
	if operator == "~=" then return value ~= target end
	if operator == ">" then return value > target end
	if operator == "<" then return value < target end
	if operator == "<=" then return value <= target end
	return value >= target
end
-- Shared with the generic triggers (Core/GenericTriggers.lua).
PA.CompareValue = Compare

local function HasNames(trigger)
	return trigger.useName and type(trigger.auranames) == "table" and trigger.auranames[1] ~= nil
end

local function NameListed(trigger, name)
	if not name then return false end
	local i
	for i = 1, Compat.getn(trigger.auranames) do
		if trigger.auranames[i] == name then return true end
	end
	return false
end

-- The cheap checks first; the name needs a tooltip read.
local function MatchAura(trigger, aura)
	if aura.harmful and trigger.useDebuffClass and trigger.debuffClass then
		local class = aura.class and string.lower(aura.class) or "none"
		if class ~= trigger.debuffClass then return false end
	end
	if trigger.useStacks and not Compare(aura.stacks, trigger.stacksOperator or ">=", trigger.stacks) then
		return false
	end
	if trigger.useRem and aura.unit == "player" then
		if not aura.timeLeft or not Compare(aura.timeLeft, trigger.remOperator or "<=", trigger.rem) then
			return false
		end
	end
	if HasNames(trigger) and not NameListed(trigger, AuraName(aura)) then
		return false
	end
	return true
end

local function UnitExistsSafe(unit)
	local ok, exists = pcall(UnitExists, unit)
	return ok and Compat.bool(exists)
end

-- The unit ids a trigger looks at.
local function TriggerUnits(trigger)
	local unit = trigger.unit or "player"
	local units = {}
	local i

	if unit == "member" then
		if trigger.specificUnit and trigger.specificUnit ~= "" then
			table.insert(units, trigger.specificUnit)
		end
	elseif unit == "party" then
		for i = 1, 4 do table.insert(units, "party" .. i) end
	elseif unit == "raid" then
		for i = 1, 40 do table.insert(units, "raid" .. i) end
	elseif unit == "group" then
		local okRaid, raidCount = pcall(GetNumRaidMembers)
		if okRaid and (tonumber(raidCount) or 0) > 0 then
			for i = 1, 40 do table.insert(units, "raid" .. i) end
		else
			table.insert(units, "player")
			for i = 1, 4 do table.insert(units, "party" .. i) end
		end
	else
		table.insert(units, unit)
	end
	return units
end

-- The full duration of a player aura, which the 1.12.1 client does not
-- report: as for weapon enchants, the time left when the aura is first seen
-- in its slot stands for it, until it is renewed (its expiration time moves
-- by more than a second) or another aura takes the slot.
local auraDurations = {}

local function AuraDuration(aura, expirationTime)
	local memo = auraDurations[aura.slotKey]
	if not (memo and memo.icon == aura.icon
		and math.abs(memo.expirationTime - expirationTime) <= 1) then
		memo = { icon = aura.icon, duration = aura.timeLeft }
		auraDurations[aura.slotKey] = memo
	end
	memo.expirationTime = expirationTime
	return memo.duration
end

-- The icon a trigger stands for while nothing was found: that of its first
-- aura name with a known icon (WeakAuras' BuffTrigger.GetNameAndIconSimple),
-- the names in the player's or the pet's spellbook taken first. Icons come
-- from the icon cache, which is account-wide: without the spellbook pass a
-- name seen on another character would win over the player's own spell.
-- Returns the icon and the name it belongs to; with no known icon, no icon
-- and the first name.
local function NameIcon(trigger)
	if not HasNames(trigger) then return end
	local names = trigger.auranames
	local count = Compat.getn(names)
	local i
	for i = 1, count do
		if PA:KnowsSpell(names[i]) then
			local icon = PA:GetCachedIcon(names[i])
			if icon then return icon, names[i] end
		end
	end
	for i = 1, count do
		local icon = PA:GetCachedIcon(names[i])
		if icon then return icon, names[i] end
	end
	return nil, names[1]
end

local function EvaluateAuraTrigger(trigger)
	local harmful = trigger.debuffType == "HARMFUL"
	local raidFilter = trigger.useRaidFilter and true or false
	local found

	local units = TriggerUnits(trigger)
	local u
	for u = 1, Compat.getn(units) do
		local unit = units[u]
		if UnitExistsSafe(unit) then
			local auras = GetAuras(unit, harmful, raidFilter)
			local a
			for a = 1, Compat.getn(auras) do
				if MatchAura(trigger, auras[a]) then
					found = auras[a]
					break
				end
			end
		end
		if found then break end
	end

	local showOn = trigger.matchesShowOn or "showOnActive"
	local state = {
		found = found and true or false,
		active = (showOn == "showAlways")
			or (showOn == "showOnActive" and found ~= nil)
			or (showOn == "showOnMissing" and found == nil),
	}
	if found then
		state.icon = found.icon
		state.name = AuraName(found)
		state.stacks = found.stacks
		state.applications = found.applications
		-- WeakAuras' debuffClass, lowercased as its keys ("magic", ...,
		-- "none"), for a debuff; conditions test it.
		if found.harmful then
			state.debuffClass = found.class and string.lower(found.class) or "none"
		end
		state.timeLeft = found.timeLeft
		-- A time left of 0 is an aura without a duration.
		if found.timeLeft and found.timeLeft > 0 then
			state.expirationTime = GetTime() + found.timeLeft
			state.duration = AuraDuration(found, state.expirationTime)
			state.progressType = "timed"
		end
		state.unit = found.unit
	else
		state.icon, state.name = NameIcon(trigger)
	end
	return state
end

-- Weapon enchants ----------------------------------------------------------------

-- WeakAuras' "Weapon Enchant" trigger (GenericTrigger.lua TenchInit,
-- Prototypes.lua). GetWeaponEnchantInfo reports the main and the off hand
-- (has enchant, milliseconds left, charges); the 1.12.1 client reports no
-- ranged slot and no enchant id there. Unreal Azeroth reports the time left
-- in fractional milliseconds, and 0 charges for an enchant without charges.
-- The client does not report the enchant's full duration: as in WeakAuras,
-- the time left when an enchant is first seen stands for it.
local WEAPON_SLOTS = { main = 16, off = 17 }
local tench = { main = {}, off = {} }

-- The enchant's name, from the weapon tooltip's "<name> (<n> min)" line
-- (ITEM_ENCHANT_TIME_LEFT_*), with WeakAuras' pattern: "Rockbiter 2 (1 min)"
-- gives the name "Rockbiter 2" and the shortened name "Rockbiter", without
-- the rank. Colour codes are stripped first.
local function TenchName(slot)
	local lines = ScanTooltip("SetInventoryItem", "player", slot)
	local i
	for i = 1, Compat.getn(lines) do
		local text = string.gsub(lines[i], "|c%x%x%x%x%x%x%x%x", "")
		text = string.gsub(text, "|r", "")
		local _, _, name, shortened = string.find(text, "^((.-) ?+?[XVI%d]*) ?%(%d+%D+%)$")
		if name and name ~= "" then return name, shortened end
	end
end

-- One hand's enchant. Its expiration time only moves when it differs by more
-- than a second from the one kept (a new or renewed enchant), and only then
-- is the tooltip read; a name not found yet is looked for again.
local function ReadHand(hand, has, remaining, charges, now)
	local info = tench[hand]
	local slot = WEAPON_SLOTS[hand]
	local expiration
	if has and remaining then expiration = now + remaining / 1000 end

	if math.abs((info.expirationTime or 0) - (expiration or 0)) > 1 then
		info.expirationTime = expiration
		info.duration = expiration and remaining / 1000 or nil
		info.name, info.shortenedName = nil, nil
	end
	if info.expirationTime and not info.name then
		info.name, info.shortenedName = TenchName(slot)
	end

	info.charges = has and tonumber(charges) or nil
	local ok, icon = pcall(GetInventoryItemTexture, "player", slot)
	info.icon = ok and icon or nil
end

-- Whether the enchants were read during this evaluation.
local passTench

local function ReadTench()
	if passTench then return end
	passTench = true
	local ok, mh, mhRem, mhCharges, oh, ohRem, ohCharges = pcall(GetWeaponEnchantInfo)
	if not ok then mh, oh = nil, nil end
	local now = GetTime()
	ReadHand("main", Compat.bool(mh), tonumber(mhRem), mhCharges, now)
	ReadHand("off", Compat.bool(oh), tonumber(ohRem), ohCharges, now)
end

-- The enchant filter matches the name or the shortened name. As in
-- WeakAuras, the charge and remaining time filters apply only when the
-- trigger shows on a found enchant.
local function EvaluateWeaponEnchant(trigger)
	ReadTench()
	local info = tench[trigger.weapon or "main"] or tench.main
	local showOn = trigger.showOn or "showOnActive"
	local remaining = info.expirationTime and info.expirationTime - GetTime()

	local found = info.expirationTime ~= nil
	if found and trigger.use_enchant and trigger.enchant and trigger.enchant ~= "" then
		found = trigger.enchant == info.name or trigger.enchant == info.shortenedName
	end
	if found and showOn == "showOnActive" then
		if trigger.use_stacks and not Compare(info.charges, trigger.stacks_operator or "<", trigger.stacks) then
			found = false
		end
		if found and trigger.use_remaining
			and not (remaining and Compare(remaining, trigger.remaining_operator or "<", trigger.remaining)) then
			found = false
		end
	end

	local state = {
		found = found,
		active = (showOn == "showAlways")
			or (showOn == "showOnActive" and found)
			or (showOn == "showOnMissing" and not found),
		icon = info.icon,
		name = info.name,
	}
	if found then
		state.stacks = info.charges
		state.timeLeft = remaining
		state.expirationTime = info.expirationTime
		state.duration = info.duration
		state.progressType = "timed"
	end
	return state
end

-- Unit values ----------------------------------------------------------------------

-- WeakAuras' "Health" and "Power" triggers (Prototypes.lua). A unit's value
-- and total give the percent (nil for a total of 0), the deficit and the
-- maximum, each with a number filter under WeakAuras' field names, in this
-- order: value, percent, deficit, maximum.
local UNIT_VALUE_FIELDS = {
	Health = { "health", "percenthealth", "deficit", "maxhealth" },
	Power = { "power", "percentpower", "deficit", "maxpower" },
}

-- WeakAuras' power type of combo points.
local POWER_COMBO_POINTS = 4

-- WeakAuras' multiEntry number filter: <name> and <name>_operator are lists
-- whose entries must all hold ("==" when an entry has no operator); a
-- single value outside a list counts as one entry. An entry that is not a
-- number is ignored, and a value of nil fails every entry.
local function MatchEntries(trigger, name, value)
	if not trigger["use_" .. name] then return true end
	local targets, operators = trigger[name], trigger[name .. "_operator"]
	if type(targets) ~= "table" then targets = { targets } end
	local i
	for i = 1, Compat.getn(targets) do
		if tonumber(targets[i]) then
			if value == nil then return false end
			local operator = operators
			if type(operators) == "table" then operator = operators[i] end
			if not Compare(value, operator or "==", targets[i]) then return false end
		end
	end
	return true
end
PA.MatchEntries = MatchEntries

-- For a unit outside the player's group the client reports health as a
-- percent: UnitHealthMax is 100.
local function ReadHealth(unit)
	local okValue, value = pcall(UnitHealth, unit)
	local okTotal, total = pcall(UnitHealthMax, unit)
	return tonumber(okValue and value) or 0, tonumber(okTotal and total) or 0
end

-- The client reports only a unit's primary power (UnitMana, with
-- UnitPowerType's 0-3 matching WeakAuras' mana, rage, focus, energy), so a
-- unit whose primary power is not the chosen type gives no value: WeakAuras'
-- "Only if Primary", always on. Combo points come from GetComboPoints, which
-- reports the player's points on the current target alone. UnitPowerType's
-- 4 is a pet's happiness, which is not offered. A power type not picked yet
-- is mana, as the options show it.
local function ReadPower(trigger, unit)
	local powerType
	if trigger.use_powertype then powerType = tonumber(trigger.powertype) or 0 end
	if powerType == POWER_COMBO_POINTS then
		if unit ~= "player" then return nil end
		local ok, points = pcall(GetComboPoints)
		return tonumber(ok and points) or 0, MAX_COMBO_POINTS or 5
	end
	if powerType then
		local ok, unitType = pcall(UnitPowerType, unit)
		if not ok or tonumber(unitType) ~= powerType then return nil end
	end
	local okValue, value = pcall(UnitMana, unit)
	local okTotal, total = pcall(UnitManaMax, unit)
	return tonumber(okValue and value) or 0, tonumber(okTotal and total) or 0
end

-- The first of the trigger's units whose values pass every filter. The
-- state carries WeakAuras' static progress: value, total, progressType.
local function EvaluateUnitValue(trigger)
	local fields = UNIT_VALUE_FIELDS[trigger.event]
	local units = TriggerUnits(trigger)
	local u
	for u = 1, Compat.getn(units) do
		local unit = units[u]
		if UnitExistsSafe(unit) then
			local value, total
			if trigger.event == "Health" then
				value, total = ReadHealth(unit)
			else
				value, total = ReadPower(trigger, unit)
			end
			if value then
				local percent
				if total ~= 0 then percent = value / total * 100 end
				if MatchEntries(trigger, fields[1], value)
					and MatchEntries(trigger, fields[2], percent)
					and MatchEntries(trigger, fields[3], total - value)
					and MatchEntries(trigger, fields[4], total) then
					local okName, name = pcall(UnitName, unit)
					-- The value, percent, deficit and maximum also go under
					-- WeakAuras' names (health, percenthealth, deficit,
					-- maxhealth; power ...), which conditions test.
					local state = {
						active = true,
						found = true,
						progressType = "static",
						value = value,
						total = total,
						unit = unit,
						name = okName and name or nil,
					}
					state[fields[1]] = value
					state[fields[2]] = percent
					state[fields[3]] = total - value
					state[fields[4]] = total
					return state
				end
			end
		end
	end
	return { active = false, found = false }
end

-- Triggers -----------------------------------------------------------------------

-- The generic trigger of Core/GenericTriggers.lua a trigger's data names.
local function GenericTrigger(trigger)
	local byEvent = PA.genericTriggers and PA.genericTriggers[trigger.type or ""]
	return byEvent and byEvent[trigger.event or ""]
end

-- Which evaluator a trigger's data belongs to: "aura" (WeakAuras' aura2),
-- "weaponEnchant" (the generic "item" trigger's "Weapon Enchant" event),
-- "unitValue" (the generic "unit" trigger's "Health" and "Power" events),
-- "generic" (Core/GenericTriggers.lua), or nil for a trigger of a kind not
-- supported.
local function TriggerKind(trigger)
	if not trigger then return nil end
	if trigger.type == "aura2" then return "aura" end
	if trigger.type == "item" and trigger.event == "Weapon Enchant" then return "weaponEnchant" end
	if trigger.type == "unit" and UNIT_VALUE_FIELDS[trigger.event or ""] then return "unitValue" end
	if GenericTrigger(trigger) then return "generic" end
end

-- Errors of generic evaluators already printed, by their text.
local reportedErrors = {}

-- A generic trigger's state. A failing evaluator costs its own trigger,
-- not the whole evaluation; its error is printed to the chat once.
local function EvaluateGeneric(trigger)
	local ok, result = pcall(GenericTrigger(trigger).evaluate, trigger)
	if ok and type(result) == "table" then return result end
	local message = tostring(result)
	if not reportedErrors[message] then
		reportedErrors[message] = true
		DEFAULT_CHAT_FRAME:AddMessage("PunyAuras: " .. tostring(trigger.event) .. ": " .. message)
	end
	return { active = false }
end

-- Whether the last evaluation had a loaded unit value trigger; the health
-- and power events only matter then.
local watchUnitValues = false

-- The icon of a trigger that is not evaluated: the aura names' cached icon,
-- or the weapon's own.
local function IdleIcon(trigger)
	local kind = TriggerKind(trigger)
	if kind == "aura" then return NameIcon(trigger) end
	if kind == "weaponEnchant" then
		local slot = WEAPON_SLOTS[trigger.weapon or "main"] or WEAPON_SLOTS.main
		local ok, icon = pcall(GetInventoryItemTexture, "player", slot)
		return ok and icon or nil
	end
	if kind == "generic" then
		local generic = GenericTrigger(trigger)
		if generic.idleIcon then
			local ok, icon = pcall(generic.idleIcon, trigger)
			return ok and icon or nil
		end
	end
end

-- Auras ------------------------------------------------------------------------

-- The state of an aura. The triggers of an aura that is not loaded are not
-- evaluated: they are inactive and keep only their idle icon, which the
-- options list shows.
local function EvaluateAura(data, loaded)
	local triggers = data.triggers
	local states = {}
	local anyActive, allActive = false, true
	local i
	for i = 1, Compat.getn(triggers) do
		local trigger = triggers[i].trigger
		local kind = TriggerKind(trigger)
		local state
		if not kind then
			state = { active = false }
		elseif not loaded then
			state = { active = false, icon = IdleIcon(trigger) }
		elseif kind == "weaponEnchant" then
			state = EvaluateWeaponEnchant(trigger)
		elseif kind == "unitValue" then
			watchUnitValues = true
			state = EvaluateUnitValue(trigger)
		elseif kind == "generic" then
			state = EvaluateGeneric(trigger)
		else
			state = EvaluateAuraTrigger(trigger)
		end
		states[i] = state
		if state.active then anyActive = true else allActive = false end
	end

	local active
	if Compat.getn(triggers) == 0 then
		active = false
	elseif triggers.disjunctive == "all" then
		active = allActive
	else
		active = anyActive
	end
	return { active = active, triggers = states }
end

-- Two expiration times of the same aura; they differ by the rounding of the
-- time left between evaluations, and by far more once the aura is renewed.
local EXPIRATION_TOLERANCE = 0.5

local function SameExpiration(a, b)
	if a == nil or b == nil then return a == b end
	return math.abs(a - b) < EXPIRATION_TOLERANCE
end

-- Whether a region has anything new to show: the aura's activity, the
-- conditions that hold (Core/Conditions.lua), or a trigger's activity, icon
-- or expiration time (which a dynamic group sorts by).
local function SameState(a, b)
	if not (a and b) or a.active ~= b.active then return false end
	if a.conditionKey ~= b.conditionKey then return false end
	local count = Compat.getn(a.triggers)
	if count ~= Compat.getn(b.triggers) then return false end
	local i
	for i = 1, count do
		local ta, tb = a.triggers[i], b.triggers[i]
		if ta.active ~= tb.active or ta.icon ~= tb.icon then return false end
		if not SameExpiration(ta.expirationTime, tb.expirationTime) then return false end
	end
	return true
end

-- The trigger state an aura's progress comes from (WeakAuras' automatic
-- progress source): the first active trigger that reports a progress,
-- "timed" (duration, expirationTime) or "static" (value, total); nil when
-- none does.
function PA:StateProgress(state)
	if not state then return nil end
	local i
	for i = 1, Compat.getn(state.triggers) do
		local trigger = state.triggers[i]
		if trigger.active and trigger.progressType then return trigger end
	end
end

-- The icon the triggers give an aura: trigger `source` (n > 0), or the first
-- active trigger's, or while none is active the first trigger with any icon.
function PA:StateIcon(state, source)
	if not state then return nil end
	local triggers = state.triggers
	if source and source > 0 then
		return triggers[source] and triggers[source].icon
	end
	local i
	for i = 1, Compat.getn(triggers) do
		if triggers[i].active and triggers[i].icon then return triggers[i].icon end
	end
	for i = 1, Compat.getn(triggers) do
		if triggers[i].icon then return triggers[i].icon end
	end
end

-- `PA.onAuraStatesChanged`, when set (the options window), runs after an
-- evaluation that changed any aura's state or load state. Groups have no
-- triggers and no load conditions, and so no state.
-- The earliest time an evaluated trigger changes without an event (a
-- cooldown running out); the next evaluation runs then.
local wakeAt

function PA:WakeTriggersAt(time)
	if time and (not wakeAt or time < wakeAt) then wakeAt = time end
end

local function EvaluateAll()
	passAuras = {}
	passTench = nil
	watchUnitValues = false
	wakeAt = nil
	PA:BeginGenericPass()
	local env = PA:LoadEnvironment()
	local seen = {}
	local changed = false
	local id, data
	for id, data in pairs(PA.db.global.displays) do
		if not PA:IsGroup(data) then
			seen[id] = true
			local loaded = PA:CheckLoad(data, env)
			if PA.loaded[id] ~= loaded then
				PA.loaded[id] = loaded
				changed = true
			end
			local state = EvaluateAura(data, loaded == true)
			PA:ApplyConditions(data, state)
			local old = PA.auraStates[id]
			PA.auraStates[id] = state
			PA:RunActions(data, old, state)
			if not SameState(old, state) then
				changed = true
				PA:RefreshRegion(id)
			else
				-- A progress change alone (health, power) only updates the
				-- region's progress, not the whole region or the list.
				PA:UpdateRegionProgress(id)
			end
		end
	end
	for id in pairs(PA.auraStates) do
		if not seen[id] then PA.auraStates[id] = nil end
	end
	for id in pairs(PA.loaded) do
		if not seen[id] then PA.loaded[id] = nil end
	end
	passAuras = nil

	if changed and PA.onAuraStatesChanged then
		PA.onAuraStatesChanged()
	end
end

-- Icon harvest ------------------------------------------------------------------

-- Feeds the icon cache from the units around the player, not only the ones
-- a trigger watches: every icon not seen this session has its name read once.
local HARVEST_UNITS = { "player", "target", "pet", "party1", "party2", "party3", "party4" }
local harvested = {}

local function Harvest()
	local u
	for u = 1, Compat.getn(HARVEST_UNITS) do
		local unit = HARVEST_UNITS[u]
		if UnitExistsSafe(unit) then
			local kind
			for kind = 1, 2 do
				local harmful = (kind == 2)
				local auras
				if unit == "player" then
					auras = CollectPlayerAuras(harmful, false)
				else
					auras = CollectUnitAuras(unit, harmful, false)
				end
				local a
				for a = 1, Compat.getn(auras) do
					local aura = auras[a]
					if not harvested[aura.icon] then
						harvested[aura.icon] = true
						AuraName(aura)
					end
				end
			end
		end
	end
end

-- Scheduling -------------------------------------------------------------------

local dirty = true
local harvestDirty = true
local lastEvaluate, lastBackstop = 0, 0
local driver

-- Marks the aura states for re-evaluation on the next update.
function PA:ScheduleTriggerUpdate()
	dirty = true
end

local EVENTS = {
	"UNIT_AURA",
	"PLAYER_AURAS_CHANGED",
	"PLAYER_TARGET_CHANGED",
	"UNIT_PET",
	"PARTY_MEMBERS_CHANGED",
	"RAID_ROSTER_UPDATE",
	"PLAYER_ENTERING_WORLD",
	"SPELLS_CHANGED",
	"LEARNED_SPELL_IN_TAB",
	-- Weapon enchants and the weapons' icons.
	"UNIT_INVENTORY_CHANGED",
	-- Load conditions (Core/Load.lua).
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_DEAD",
	"PLAYER_ALIVE",
	"PLAYER_UNGHOST",
	"PLAYER_LEVEL_UP",
	"ZONE_CHANGED",
	"ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA",
}

-- The health and power triggers' events. They come often (every unit in a
-- raid, every energy tick), so they schedule an evaluation only while a
-- unit value trigger is loaded, and never the icon harvest.
local UNIT_VALUE_EVENTS = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_MANA",
	"UNIT_RAGE",
	"UNIT_FOCUS",
	"UNIT_ENERGY",
	"UNIT_MAXMANA",
	"UNIT_MAXRAGE",
	"UNIT_MAXFOCUS",
	"UNIT_MAXENERGY",
	"UNIT_DISPLAYPOWER",
	"PLAYER_COMBO_POINTS",
}
local isUnitValueEvent = {}

-- The generic triggers' events (Core/GenericTriggers.lua). They only
-- schedule an evaluation, not the icon harvest; bag updates come often.
local GENERIC_EVENTS = {
	"SPELL_UPDATE_COOLDOWN",
	"ACTIONBAR_UPDATE_COOLDOWN",
	"BAG_UPDATE",
	"BAG_UPDATE_COOLDOWN",
	"BANKFRAME_OPENED",
	"BANKFRAME_CLOSED",
	"PLAYERBANKSLOTS_CHANGED",
	"PLAYER_XP_UPDATE",
	"UPDATE_EXHAUSTION",
	"UPDATE_FACTION",
	"PLAYER_MONEY",
	"UPDATE_SHAPESHIFT_FORMS",
	"UPDATE_SHAPESHIFT_FORM",
	"CHARACTER_POINTS_CHANGED",
	"PET_BAR_UPDATE",
	"PLAYER_UPDATE_RESTING",
	"PLAYER_FLAGS_CHANGED",
	"UNIT_FACTION",
}
local isGenericEvent = {}

function PA:InitializeTriggers()
	driver = CreateFrame("Frame")

	local i
	for i = 1, Compat.getn(EVENTS) do
		pcall(driver.RegisterEvent, driver, EVENTS[i])
	end
	for i = 1, Compat.getn(UNIT_VALUE_EVENTS) do
		isUnitValueEvent[UNIT_VALUE_EVENTS[i]] = true
		pcall(driver.RegisterEvent, driver, UNIT_VALUE_EVENTS[i])
	end
	for i = 1, Compat.getn(GENERIC_EVENTS) do
		isGenericEvent[GENERIC_EVENTS[i]] = true
		pcall(driver.RegisterEvent, driver, GENERIC_EVENTS[i])
	end
	-- The event name arrives in the `event` global on the 1.12.1 client and
	-- as the second argument on a client that passes (frame, event).
	driver:SetScript("OnEvent", function(a1, a2)
		local name = (type(a2) == "string" and a2) or event
		if isUnitValueEvent[name] then
			if watchUnitValues then dirty = true end
			return
		end
		if isGenericEvent[name] then
			dirty = true
			return
		end
		if name == "SPELLS_CHANGED" or name == "LEARNED_SPELL_IN_TAB"
			or name == "PLAYER_ENTERING_WORLD" then
			PA:CacheSpellbook()
			PA:InvalidateKnownSpells()
		elseif name == "UNIT_PET" then
			PA:InvalidateKnownSpells()
		end
		dirty = true
		harvestDirty = true
	end)

	driver:SetScript("OnUpdate", function()
		local now = GetTime()
		if now - lastBackstop >= BACKSTOP_INTERVAL then
			lastBackstop = now
			dirty = true
		end
		if wakeAt and now >= wakeAt then
			wakeAt = nil
			dirty = true
		end
		if not dirty or now - lastEvaluate < EVALUATE_INTERVAL then return end
		lastEvaluate = now
		dirty = false
		if harvestDirty then
			harvestDirty = false
			Harvest()
		end
		EvaluateAll()
	end)

	self:CacheSpellbook()
end
