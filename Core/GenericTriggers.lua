-- WeakAuras' generic triggers (Prototypes.lua event_prototypes, GPLv2) that
-- the 1.12.1 API can answer, beyond the weapon enchant and the health and
-- power triggers of Core/Triggers.lua. Each is registered in
-- PA.genericTriggers[type][event] with its `evaluate(trigger)`, which
-- returns a trigger state (Core/Triggers.lua header), and optionally
-- `idleIcon(trigger)` for a trigger that is not evaluated. Field names are
-- WeakAuras'. The filters use the load conditions' checks
-- (PA:ConditionHolds): a tristate is use_<name> true / false / nil, a
-- multiselect use_<name> with <name>.single or <name>.multi, a number
-- use_<name>, <name> and <name>_operator; the multiEntry number filters of
-- WeakAuras (lists) go through PA.MatchEntries.
--
-- The 1.12.1 client's limits, per trigger:
--   * Cooldowns: GetSpellCooldown takes a spellbook index (the spell is
--     looked up by name, its highest rank); there are no charges. The
--     global cooldown is told apart by its length: a cooldown of at most
--     GCD_MAX seconds is taken to be it. An item cooldown is read from the bag
--     or equipment slot the item is in (GetContainerItemCooldown,
--     GetInventoryItemCooldown); an item in neither has no cooldown to
--     read, and its trigger is inactive.
--   * Items are found by name, read from their links; the bank's bags only
--     count while the bank is open.
--   * Faction Reputation looks the faction up by name among the factions
--     the reputation list shows (the 1.12.1 client has no faction ids), so
--     a faction under a collapsed header is not found.
--   * Talents are keyed as in WeakAuras' Classic: (tab - 1) *
--     MAX_NUM_TALENTS + index.
--   * Conditions: the client has no mounted, moving or AFK state.
-- A cooldown's end is not always announced by an event: the trigger engine
-- is woken at the time it runs out (PA:WakeTriggersAt).

local _G = _G or getfenv()
local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

PA.genericTriggers = { spell = {}, item = {}, unit = {} }

-- The longest cooldown taken to be the global cooldown. The client reports
-- the 1.5 second GCD as a single-precision float (1.5000001192093), so
-- the limit has room above it; 1.9 as ElvUI's cooldown text uses. A spell
-- of its own cooldown up to 1.9 seconds would count as the GCD.
local GCD_MAX = 1.9
local TALENTS_PER_TAB = 20
local EQUIPMENT_SLOTS = 19
local BAGS = { 0, 1, 2, 3, 4 }
local BANK_BAGS = { -1, 5, 6, 7, 8, 9, 10 }
PA.MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local function Trim(text)
	text = string.gsub(text or "", "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return text
end

local function Register(triggerType, event, evaluate, idleIcon)
	PA.genericTriggers[triggerType][event] = { evaluate = evaluate, idleIcon = idleIcon }
end

-- Values read during one evaluation, shared by every trigger that needs
-- them (bag contents, the global cooldown); cleared by
-- PA:BeginGenericPass.
local pass = {}

function PA:BeginGenericPass()
	pass = {}
end

-- A trigger's state from whether it matched, and its "show on" setting;
-- `fields` are copied onto the state.
local function State(found, showOn, fields)
	local state = fields or {}
	state.found = found and true or false
	state.active = (showOn == "showAlways")
		or ((showOn == nil or showOn == "showOnActive") and state.found)
		or (showOn == "showOnMissing" and not state.found)
	return state
end

-- The name in an item link, "|Hitem:...|h[Name]|h".
local function LinkName(link)
	if type(link) ~= "string" then return nil end
	local _, _, name = string.find(link, "%[(.+)%]")
	return name
end

-- Cooldowns ---------------------------------------------------------------------

-- A cooldown as the client reports it, as (on cooldown, start, duration).
-- The global cooldown counts only with `showGCD`.
local function ReadCooldown(start, duration, enable, showGCD)
	start, duration = tonumber(start) or 0, tonumber(duration) or 0
	if not Compat.bool(enable) or start <= 0 or duration <= 0 then return false end
	if start + duration <= GetTime() then return false end
	if duration <= GCD_MAX and not showGCD then return false end
	return true, start, duration
end

-- WeakAuras' cooldown progress state: genericShowOn "showOnCooldown"
-- (default), "showOnReady" or "showAlways"; the remaining time filter
-- applies on cooldown. The engine is woken when the cooldown ends, and when
-- it crosses the remaining time filter's value.
local function CooldownState(trigger, onCooldown, start, duration, icon, name)
	local showOn = trigger.genericShowOn or "showOnCooldown"
	local state = { icon = icon, name = name, found = onCooldown and true or false,
		onCooldown = onCooldown and true or false }
	local matches = onCooldown
	if onCooldown then
		local expiration = start + duration
		state.progressType = "timed"
		state.duration = duration
		state.expirationTime = expiration
		PA:WakeTriggersAt(expiration)
		if trigger.use_remaining and tonumber(trigger.remaining) then
			local remaining = expiration - GetTime()
			local target = tonumber(trigger.remaining)
			matches = PA.CompareValue(remaining, trigger.remaining_operator or "<", target)
			if remaining > target then PA:WakeTriggersAt(expiration - target) end
		end
	end
	state.active = (showOn == "showAlways")
		or (showOn == "showOnCooldown" and matches)
		or (showOn == "showOnReady" and not onCooldown)
	return state
end

local function SpellIcon(name)
	local index, book = PA:FindSpell(name)
	if index then
		local ok, icon = pcall(GetSpellTexture, index, book)
		if ok and icon then return icon end
	end
	return PA:GetCachedIcon(name)
end

-- WeakAuras' "Cooldown Progress (Spell)". A spell not in the spellbook
-- gives an inactive trigger.
local function SpellCooldown(trigger)
	local name = Trim(trigger.spellName)
	local index, book = PA:FindSpell(name)
	if not index then return { active = false, found = false, icon = PA:GetCachedIcon(name), name = name } end
	local okIcon, icon = pcall(GetSpellTexture, index, book)
	local ok, start, duration, enable = pcall(GetSpellCooldown, index, book)
	local onCooldown
	if ok then onCooldown, start, duration = ReadCooldown(start, duration, enable, trigger.use_showgcd) end
	return CooldownState(trigger, onCooldown, start, duration, okIcon and icon or nil, name)
end
Register("spell", "Cooldown Progress (Spell)", SpellCooldown,
	function(trigger) return SpellIcon(Trim(trigger.spellName)) end)

-- The global cooldown, as (start, duration), from any spellbook spell on a
-- cooldown of at most GCD_MAX; the spell found last time is tried first.
local gcdIndex

local function OnGCD(index)
	local ok, start, duration, enable = pcall(GetSpellCooldown, index, "spell")
	if not ok then return nil end
	start, duration = tonumber(start) or 0, tonumber(duration) or 0
	if Compat.bool(enable) and start > 0 and duration > 0 and duration <= GCD_MAX
		and start + duration > GetTime() then
		return start, duration
	end
end

local function ReadGCD()
	if pass.gcd then return pass.gcd.start, pass.gcd.duration end
	local start, duration
	if gcdIndex then start, duration = OnGCD(gcdIndex) end
	if not start then
		local i = 1
		while true do
			local ok, name = pcall(GetSpellName, i, "spell")
			if not ok or not name then break end
			start, duration = OnGCD(i)
			if start then
				gcdIndex = i
				break
			end
			i = i + 1
		end
	end
	pass.gcd = { start = start, duration = duration }
	return start, duration
end

-- WeakAuras' "Global Cooldown": active while it runs (`use_inverse`: while
-- it does not).
local function GlobalCooldown(trigger)
	local start, duration = ReadGCD()
	local state = { found = start ~= nil, name = L["Global Cooldown"] }
	if start then
		state.progressType = "timed"
		state.duration = duration
		state.expirationTime = start + duration
		PA:WakeTriggersAt(start + duration)
	end
	state.active = state.found
	if trigger.use_inverse then state.active = not state.active end
	return state
end
Register("spell", "Global Cooldown", GlobalCooldown)

-- WeakAuras' "Spell Known"; `use_petspell` looks in the pet's book alone.
local function SpellKnown(trigger)
	local name = Trim(trigger.spellName)
	local index, book = PA:FindSpell(name)
	local known = index ~= nil
	if trigger.use_petspell then known = known and book == "pet" end
	local active = known
	if trigger.use_inverse then active = not active end
	return { active = active, found = known, icon = SpellIcon(name), name = name }
end
Register("spell", "Spell Known", SpellKnown,
	function(trigger) return SpellIcon(Trim(trigger.spellName)) end)

-- Items -------------------------------------------------------------------------

-- The items in `bags` by lowercased name: { count, bag, slot, icon, name }
-- with the first slot an item is in.
local function ScanBags(bags)
	local items = {}
	local b
	for b = 1, Compat.getn(bags) do
		local bag = bags[b]
		local okSlots, slots = pcall(GetContainerNumSlots, bag)
		slots = okSlots and tonumber(slots) or 0
		local slot
		for slot = 1, slots do
			local okLink, link = pcall(GetContainerItemLink, bag, slot)
			local name = okLink and LinkName(link)
			if name then
				local okInfo, icon, count = pcall(GetContainerItemInfo, bag, slot)
				count = okInfo and tonumber(count) or 1
				local key = string.lower(name)
				local item = items[key]
				if item then
					item.count = item.count + count
				else
					items[key] = { count = count, bag = bag, slot = slot,
						icon = okInfo and icon or nil, name = name }
				end
			end
		end
	end
	return items
end

local function BagItems()
	if not pass.bags then pass.bags = ScanBags(BAGS) end
	return pass.bags
end

local function BankItems()
	if not pass.bank then pass.bank = ScanBags(BANK_BAGS) end
	return pass.bank
end

-- The equipped item in `slot`, as (name, icon).
local function SlotItem(slot)
	local okLink, link = pcall(GetInventoryItemLink, "player", slot)
	local name = okLink and LinkName(link)
	if not name then return nil end
	local okIcon, icon = pcall(GetInventoryItemTexture, "player", slot)
	return name, okIcon and icon or nil
end

-- The equipment slot item `name` is equipped in, and its icon.
local function FindEquipped(name)
	local key = string.lower(name)
	local slot
	for slot = 1, EQUIPMENT_SLOTS do
		local itemName, icon = SlotItem(slot)
		if itemName and string.lower(itemName) == key then return slot, icon end
	end
end

-- An item's icon, remembered in the icon cache under its name once seen.
local function ItemIcon(name, icon)
	if icon and name and name ~= "" then PA:CacheIcon(name, icon) end
	return icon or PA:GetCachedIcon(name)
end

-- WeakAuras' "Cooldown Progress (Equipment Slot)"; an empty slot gives an
-- inactive trigger.
local function SlotCooldown(trigger)
	local slot = tonumber(trigger.itemSlot) or 13
	local name, icon = SlotItem(slot)
	if not name then return { active = false, found = false } end
	local ok, start, duration, enable = pcall(GetInventoryItemCooldown, "player", slot)
	local onCooldown
	if ok then onCooldown, start, duration = ReadCooldown(start, duration, enable, trigger.use_showgcd) end
	return CooldownState(trigger, onCooldown, start, duration, ItemIcon(name, icon), name)
end
Register("item", "Cooldown Progress (Equipment Slot)", SlotCooldown, function(trigger)
	local _, icon = SlotItem(tonumber(trigger.itemSlot) or 13)
	return icon
end)

-- WeakAuras' "Cooldown Progress (Item)": the item in the bags or equipped.
local function ItemCooldown(trigger)
	local name = Trim(trigger.itemName)
	if name == "" then return { active = false, found = false } end
	local ok, start, duration, enable, icon
	local slot
	slot, icon = FindEquipped(name)
	if slot then
		ok, start, duration, enable = pcall(GetInventoryItemCooldown, "player", slot)
	else
		local item = BagItems()[string.lower(name)]
		if not item then return { active = false, found = false, icon = ItemIcon(name), name = name } end
		icon = item.icon
		ok, start, duration, enable = pcall(GetContainerItemCooldown, item.bag, item.slot)
	end
	local onCooldown
	if ok then onCooldown, start, duration = ReadCooldown(start, duration, enable, trigger.use_showgcd) end
	return CooldownState(trigger, onCooldown, start, duration, ItemIcon(name, icon), name)
end
Register("item", "Cooldown Progress (Item)", ItemCooldown,
	function(trigger) return ItemIcon(Trim(trigger.itemName)) end)

-- WeakAuras' "Item Equipped": in the chosen slot (use_itemSlot) or any;
-- `use_inverse` shows it while not equipped.
local function ItemEquipped(trigger)
	local name = Trim(trigger.itemName)
	local icon, equipped
	if name ~= "" then
		if trigger.use_itemSlot then
			local slotName, slotIcon = SlotItem(tonumber(trigger.itemSlot) or 1)
			equipped = slotName ~= nil and string.lower(slotName) == string.lower(name)
			if equipped then icon = slotIcon end
		else
			local slot
			slot, icon = FindEquipped(name)
			equipped = slot ~= nil
		end
	end
	local active = equipped and true or false
	if trigger.use_inverse then active = not active end
	return { active = active, found = equipped and true or false, icon = ItemIcon(name, icon), name = name }
end
Register("item", "Item Equipped", ItemEquipped,
	function(trigger) return ItemIcon(Trim(trigger.itemName)) end)

-- WeakAuras' "Item Count": the count in the bags (and the open bank's with
-- `use_includeBank`), filtered by `count`; shown as its stacks.
local function ItemCount(trigger)
	local name = Trim(trigger.itemName)
	local key = string.lower(name)
	local count, icon = 0, nil
	local item = BagItems()[key]
	if item then count, icon = item.count, item.icon end
	if trigger.use_includeBank then
		local banked = BankItems()[key]
		if banked then
			count = count + banked.count
			icon = icon or banked.icon
		end
	end
	local active = name ~= "" and PA:ConditionHolds("number", "count", trigger, count)
	return { active = active, found = active, icon = ItemIcon(name, icon), name = name,
		stacks = count, applications = count, count = count }
end
Register("item", "Item Count", ItemCount,
	function(trigger) return ItemIcon(Trim(trigger.itemName)) end)

-- Player values -----------------------------------------------------------------

local function Call(fn, a1, a2)
	local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9 = pcall(fn, a1, a2)
	if ok then return r1, r2, r3, r4, r5, r6, r7, r8, r9 end
end

local function Percent(value, total)
	if total and total ~= 0 then return value / total * 100 end
end

-- WeakAuras' "Experience" (Player Experience), a static progress.
local function Experience(trigger)
	local level = tonumber(Call(UnitLevel, "player")) or 0
	local value = tonumber(Call(UnitXP, "player")) or 0
	local total = tonumber(Call(UnitXPMax, "player")) or 0
	local rested = tonumber(Call(GetXPExhaustion)) or 0
	local percent = Percent(value, total)
	local percentRested = Percent(rested, total)
	local match = PA.MatchEntries(trigger, "level", level)
		and PA.MatchEntries(trigger, "currentXP", value)
		and PA.MatchEntries(trigger, "totalXP", total)
		and PA.MatchEntries(trigger, "percentXP", percent)
		and PA.MatchEntries(trigger, "restedXP", rested)
		and PA.MatchEntries(trigger, "percentrested", percentRested)
	return State(match, nil, {
		progressType = "static", value = value, total = total,
		level = level, currentXP = value, totalXP = total, restedXP = rested,
		percentXP = percent, percentrested = percentRested,
	})
end
Register("unit", "Experience", Experience)

-- The standing's label (FACTION_STANDING_LABEL1-8).
local function StandingLabel(standingId)
	return standingId and _G["FACTION_STANDING_LABEL" .. standingId] or nil
end

-- The reputation's (name, standingId, min, max, value): the watched
-- faction, or the one named `factionID` in the reputation list.
local function ReadFaction(trigger)
	if trigger.use_watched then
		local name, standingId, barMin, barMax, value = Call(GetWatchedFactionInfo)
		if name then return name, standingId, barMin, barMax, value end
		return nil
	end
	local wanted = trigger.factionID
	if type(wanted) ~= "string" or wanted == "" then return nil end
	local count = tonumber(Call(GetNumFactions)) or 0
	local i
	for i = 1, count do
		local name, _, standingId, barMin, barMax, value, _, _, isHeader = Call(GetFactionInfo, i)
		if name == wanted and not Compat.bool(isHeader) then
			return name, standingId, barMin, barMax, value
		end
	end
end

-- WeakAuras' "Faction Reputation", a static progress within the standing.
local function FactionReputation(trigger)
	local name, standingId, barMin, barMax, current = ReadFaction(trigger)
	if not name then return { active = false, found = false } end
	standingId = tonumber(standingId)
	local value = (tonumber(current) or 0) - (tonumber(barMin) or 0)
	local total = (tonumber(barMax) or 0) - (tonumber(barMin) or 0)
	local percent = Percent(value, total)
	local match = PA.MatchEntries(trigger, "value", value)
		and PA.MatchEntries(trigger, "total", total)
		and PA.MatchEntries(trigger, "percentRep", percent)
		and PA:ConditionHolds("number", "standingId", trigger, standingId)
	return State(match, nil, {
		progressType = "static", value = value, total = total, name = name,
		percentRep = percent, standingId = standingId, standing = StandingLabel(standingId),
	})
end
Register("unit", "Faction Reputation", FactionReputation)

-- WeakAuras' "Money" (Player Money): filtered by the gold.
local function Money(trigger)
	local money = tonumber(Call(GetMoney)) or 0
	local gold = math.floor(money / 10000)
	local silver = math.floor(Compat.mod(money, 10000) / 100)
	local copper = Compat.mod(money, 100)
	local match = PA:ConditionHolds("number", "gold", trigger, gold)
	return State(match, nil, {
		icon = PA.MONEY_ICON, money = money, gold = gold, silver = silver, copper = copper,
	})
end
Register("unit", "Money", Money, function() return PA.MONEY_ICON end)

-- Player state ------------------------------------------------------------------

-- The active shapeshift form's index (0 for none, WeakAuras' "Humanoid"),
-- icon and name, from GetShapeshiftFormInfo (icon, name, active, castable).
function PA:ActiveShapeshiftForm()
	local count = tonumber(Call(GetNumShapeshiftForms)) or 0
	local i
	for i = 1, count do
		local icon, name, active = Call(GetShapeshiftFormInfo, i)
		if Compat.bool(active) then return i, icon, name end
	end
	return 0
end

-- WeakAuras' "Stance/Form/Aura": the form multiselect; `use_inverse` flips
-- it when a form is chosen.
local function StanceForm(trigger)
	local form, icon, name = PA:ActiveShapeshiftForm()
	local match = PA:ConditionHolds("multiselect", "form", trigger, form)
	if trigger.use_form ~= nil and trigger.use_inverse then match = not match end
	return State(match, nil, { icon = icon, name = name or L["Humanoid"], form = form })
end
Register("unit", "Stance/Form/Aura", StanceForm,
	function() local _, icon = PA:ActiveShapeshiftForm() return icon end)

-- A talent's (name, icon, rank) by WeakAuras' Classic key.
function PA:TalentByKey(key)
	key = tonumber(key)
	if not key then return nil end
	local perTab = MAX_NUM_TALENTS or TALENTS_PER_TAB
	local tab = math.floor((key - 1) / perTab) + 1
	local index = Compat.mod(key - 1, perTab) + 1
	local name, icon, _, _, rank = Call(GetTalentInfo, tab, index)
	return name, icon, tonumber(rank) or 0
end

-- WeakAuras' "Talent Known" (Classic): the chosen talent (use_talent true)
-- or any of the chosen ones (false) has a rank; with none chosen it is
-- active. `use_inverse` flips it.
local function TalentKnown(trigger)
	local active, name, icon = true, nil, nil
	local picked = trigger.talent
	local function Known(key)
		local talentName, talentIcon, rank = PA:TalentByKey(key)
		name, icon = name or talentName, icon or talentIcon
		if rank > 0 then
			name, icon = talentName, talentIcon
			return true
		end
		return false
	end
	if trigger.use_talent == true then
		active = type(picked) == "table" and picked.single ~= nil and Known(picked.single)
	elseif trigger.use_talent == false then
		active = false
		if type(picked) == "table" and type(picked.multi) == "table" then
			local key, on
			for key, on in pairs(picked.multi) do
				if on and Known(key) then
					active = true
					break
				end
			end
		end
	end
	if trigger.use_inverse then active = not active end
	return { active = active and true or false, found = active and true or false, name = name, icon = icon }
end
Register("unit", "Talent Known", TalentKnown)

-- WeakAuras' "Location": zone and subzone, as the Load tab's comma lists.
local function Location(trigger)
	local zone = Call(GetRealZoneText)
	local subzone = Call(GetSubZoneText)
	local match = PA:ConditionHolds("string", "zone", trigger, zone)
		and PA:ConditionHolds("string", "subzone", trigger, subzone)
	return State(match, nil, { name = zone, zone = zone, subzone = subzone })
end
Register("unit", "Location", Location)

-- The pet's behaviour from its action bar: the active one of the mode
-- buttons (GetPetActionInfo: name, subtext, texture, isToken, isActive),
-- and that button's icon.
local PET_MODES = {
	PET_MODE_PASSIVE = "passive",
	PET_MODE_DEFENSIVE = "defensive",
	PET_MODE_AGGRESSIVE = "aggressive",
}

local function PetBehavior()
	local i
	for i = 1, NUM_PET_ACTION_SLOTS or 10 do
		local name, _, texture, isToken, isActive = Call(GetPetActionInfo, i)
		if name and PET_MODES[name] and Compat.bool(isActive) then
			if Compat.bool(isToken) and type(texture) == "string" then texture = _G[texture] or texture end
			return PET_MODES[name], texture
		end
	end
end

-- WeakAuras' "Pet Behavior" (Pet): the pet exists, and with use_behavior
-- has that behaviour (`use_inverse`: any other).
local function PetBehaviorTrigger(trigger)
	local exists = Compat.bool(Call(UnitExists, "pet"))
	if not exists then return { active = false, found = false } end
	local behavior, icon = PetBehavior()
	local match = true
	if trigger.use_behavior then
		match = behavior == trigger.behavior
		if trigger.use_inverse then match = not match end
	end
	return State(match, nil, { icon = icon, behavior = behavior, unit = "pet",
		name = Call(UnitName, "pet") })
end
Register("unit", "Pet Behavior", PetBehaviorTrigger)

-- WeakAuras' "Conditions", those the 1.12.1 client knows.
local function Conditions(trigger)
	local group = "solo"
	if (tonumber(Call(GetNumRaidMembers)) or 0) > 0 then
		group = "raid"
	elseif (tonumber(Call(GetNumPartyMembers)) or 0) > 0 then
		group = "group"
	end
	local match = PA:ConditionHolds("tristate", "incombat", trigger,
			Compat.bool(Call(UnitAffectingCombat, "player")))
		and PA:ConditionHolds("tristate", "pvpflagged", trigger, Compat.bool(Call(UnitIsPVP, "player")))
		and PA:ConditionHolds("tristate", "alive", trigger, not Compat.bool(Call(UnitIsDeadOrGhost, "player")))
		and PA:ConditionHolds("tristate", "resting", trigger, Compat.bool(Call(IsResting)))
		and PA:ConditionHolds("tristate", "HasPet", trigger, Compat.bool(Call(UnitExists, "pet")))
		and PA:ConditionHolds("multiselect", "ingroup", trigger, group)
	return State(match, nil, {})
end
Register("unit", "Conditions", Conditions)
