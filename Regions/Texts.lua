-- Text replacement: the placeholders of a text region's text and of the
-- sub-region texts (WeakAuras' Private.ReplacePlaceHolders, WeakAuras.lua,
-- and Private.dynamic_texts, Prototypes.lua; GPLv2), and the font setting
-- they share (PA:SetTextFont).
--
-- A placeholder is "%" and a symbol of letters, digits and dots, or "%{...}"
-- with any symbol in the braces; "%%" is a "%", and a "%" before any other
-- character is dropped. The symbols:
--   p  the progress: the time left of a timed progress, the value of a
--      static one
--   t  the total: the duration of a timed progress, the total of a static
--   n  the name, s the stacks (nothing below 2)
--   i  WeakAuras' inline icon, which the 1.12.1 client cannot draw in a text:
--      it is replaced by nothing
--   any other symbol names a field of the trigger state ("%unit")
-- A symbol "N.x" reads trigger N's state; the others read the first active
-- trigger's. A trigger that is not active gives nothing, as in WeakAuras.
-- "\n" typed as two characters is a line break.
--
-- Times are shown in WeakAuras' default time format: under 3 seconds with
-- one decimal, otherwise rounded up to whole seconds, over a minute as
-- "m:ss".

local PA = unpack(PunyAuras)
local Compat = PunyAuras.Compat

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

-- WeakAuras' font flags in the form SetFont takes them.
local OUTLINE_FLAGS = {
	None = "",
	OUTLINE = "OUTLINE",
	THICKOUTLINE = "THICKOUTLINE",
	MONOCHROME = "MONOCHROME",
	["MONOCHROME|OUTLINE"] = "MONOCHROME, OUTLINE",
	["MONOCHROME|THICKOUTLINE"] = "MONOCHROME, THICKOUTLINE",
}

-- Sets a font string's font: a LibSharedMedia font name, a size and one of
-- WeakAuras' font flags, falling back to the default font. On Unreal
-- Azeroth SetFont does nothing: a text keeps the font it was created with
-- (GameFontHighlight, so that it draws there). With `setTextHeight`,
-- SetTextHeight(size) is called as well -- on Unreal Azeroth that sets the
-- font string's height, not its font size, which holds the text to one
-- line (a longer one is cut off with ".."); the text region measures its
-- height by it.
function PA:SetTextFont(fontString, font, size, flags, setTextHeight)
	local path = LSM and LSM:Fetch("font", font or "", true) or DEFAULT_FONT
	flags = OUTLINE_FLAGS[flags or "None"] or ""
	if not pcall(fontString.SetFont, fontString, path, size, flags) then
		pcall(fontString.SetFont, fontString, DEFAULT_FONT, size, flags)
	end
	if setTextHeight then
		pcall(fontString.SetTextHeight, fontString, size)
	end
end

-- WeakAuras' default for %p and %t: time_dynamic_threshold 3, precision 1.
local TIME_THRESHOLD = 3

-- WeakAuras' "timed" formatter with its built-in format (simpleFormatters
-- time[99]). Nothing for a time that is not positive.
local function FormatTime(value)
	if type(value) ~= "number" or value <= 0 then return "" end
	if value < TIME_THRESHOLD then
		return string.format("%.1f", value)
	end
	value = math.ceil(value)
	if value > 60 then
		return string.format("%d:%02d", math.floor(value / 60), Compat.mod(value, 60))
	end
	return string.format("%d", value)
end

local function IsSymbolChar(char)
	return (char >= 48 and char <= 57) or (char >= 65 and char <= 90)
		or (char >= 97 and char <= 122) or char == 46
end

-- The value of symbol `sym` of trigger state `state` at `now`, as a string,
-- and whether it is a timed progress's time left (which changes every
-- frame).
local function SymbolValue(sym, state, now)
	if not state then return "", false end
	if sym == "p" then
		if state.progressType == "timed" then
			if not (state.expirationTime and state.duration) then return "", true end
			return FormatTime(state.expirationTime - now), true
		elseif state.progressType == "static" then
			return state.value ~= nil and tostring(state.value) or "", false
		end
		return "", false
	elseif sym == "t" then
		if state.progressType == "timed" then
			return FormatTime(state.duration), false
		elseif state.progressType == "static" then
			return state.total ~= nil and tostring(state.total) or "", false
		end
		return "", false
	elseif sym == "n" then
		return state.name or "", false
	elseif sym == "s" then
		-- The 1.12.1 API reports an aura that does not stack with 0 or 1
		-- applications, so, as the client's own buff and debuff frames do,
		-- a count is only shown from 2 on.
		local stacks = state.applications
		if stacks == nil then stacks = state.stacks end
		if not stacks or stacks <= 1 then return "", false end
		return tostring(stacks), false
	elseif sym == "i" then
		return "", false
	end
	local value = state[sym]
	if type(value) == "string" or type(value) == "number" then
		return tostring(value), false
	end
	return "", false
end

-- The first active trigger's state of an aura state.
local function MainState(auraState)
	if not auraState then return nil end
	local i
	for i = 1, Compat.getn(auraState.triggers) do
		if auraState.triggers[i].active then return auraState.triggers[i] end
	end
end

-- The value of a placeholder's symbol, "N.x" included.
local function ValueForSymbol(symbol, auraState, now)
	local _, _, triggerNum, sym = string.find(symbol, "^(%d+)%.(.+)$")
	if triggerNum then
		local state = auraState and auraState.triggers[tonumber(triggerNum)]
		if not (state and state.active) then return "", false end
		return SymbolValue(sym, state, now)
	end
	return SymbolValue(symbol, MainState(auraState), now)
end

-- `text` with its placeholders replaced from `auraState` (PA.auraStates[id])
-- at time `now`. The second result tells whether the text shows a time
-- left, and so has to be redrawn every frame.
function PA:FormatText(text, auraState, now)
	text = text or ""
	local parts = {}
	local ticking = false
	local length = string.len(text)
	-- WeakAuras' states: 0 plain text, 1 after "%", 2 in a symbol, 3 in
	-- braces.
	local state = 0
	local start = 1
	local pos = 1

	local function Symbol(symbol)
		local value, timed = ValueForSymbol(symbol, auraState, now)
		table.insert(parts, value)
		if timed then ticking = true end
	end

	while pos <= length do
		local char = string.byte(text, pos)
		if state == 0 then
			if char == 37 then
				if pos > start then table.insert(parts, string.sub(text, start, pos - 1)) end
				state = 1
			end
		elseif state == 1 then
			if char == 37 then
				table.insert(parts, "%")
				start = pos + 1
				state = 0
			elseif char == 123 then
				start = pos + 1
				state = 3
			elseif IsSymbolChar(char) then
				start = pos
				state = 2
			else
				-- A "%" followed by anything else is dropped, as in
				-- WeakAuras.
				start = pos
				state = 0
			end
		elseif state == 2 then
			if not IsSymbolChar(char) then
				Symbol(string.sub(text, start, pos - 1))
				if char == 37 then
					state = 1
				else
					start = pos
					state = 0
				end
			end
		else
			if char == 125 then
				Symbol(string.sub(text, start, pos - 1))
				start = pos + 1
				state = 0
			end
		end
		pos = pos + 1
	end

	if state == 0 and pos > start then
		table.insert(parts, string.sub(text, start, pos - 1))
	elseif state == 1 then
		table.insert(parts, "%")
	elseif state == 2 then
		Symbol(string.sub(text, start, pos - 1))
	end

	local result = string.gsub(table.concat(parts), "\\n", "\n")
	return result, ticking
end
