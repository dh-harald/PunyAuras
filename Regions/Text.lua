-- The text region (WeakAuras RegionTypes/Text.lua, GPLv2): a text with
-- placeholders (Regions/Texts.lua), sized to the text.
--
-- The region frame takes the text's measured size, and keeps it unscaled in
-- region.width / region.height, which a dynamic group places it by. The
-- text is anchored at its justify side, as in WeakAuras. The client-specific
-- parts:
--   * On Unreal Azeroth SetFont does nothing, so the font, its size and the
--     outline only apply on the 1.12.1 client; the text is created from
--     GameFontHighlight so that it draws on both. SetTextHeight is tried as
--     well, for the size.
--   * The 1.12.1 API has no GetStringHeight: the height is the text's own
--     GetHeight, or the font size per line when that reports nothing.
--   * A text of automatic width is never held to its measured width: it
--     stays MEASURE_WIDTH wide, anchored at its justify side, so it cannot
--     wrap however its length changes between measurements. GetStringWidth
--     reports the wrapped width of a text held to a width (a text given 13
--     pixels measures 12, however long it is), which this also avoids. The
--     width, measured line by line, only sizes the region. Sizes are only
--     kept once measured on a shown region.
--   * The 1.12.1 client has no SetWordWrap: a text of fixed width always
--     wraps, the "Elide" overflow of WeakAuras is not offered.
-- A text showing a time left is redrawn every frame; the others when the
-- aura's state or its data changes (the region's `progress` hook runs after
-- every evaluation).

local PA = unpack(PunyAuras)

local function Create(parent)
	local region = CreateFrame("Frame", nil, parent)
	region.text = region:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	region.tick = function()
		PA:RenderText(region)
	end
	region:Hide()
	return region
end

local function CountLines(text)
	local count = 1
	local pos = 1
	while true do
		local found = string.find(text, "\n", pos, true)
		if not found then return count end
		count = count + 1
		pos = found + 1
	end
end

-- A width no text reaches: the width of a text of automatic width.
local MEASURE_WIDTH = 10000

-- The widest line of `text`, each line measured on its own. Leaves the
-- whole text set.
local function MeasureWidth(fontString, text)
	local width = 0
	local pos = 1
	while true do
		local found = string.find(text, "\n", pos, true)
		local line
		if found then
			line = string.sub(text, pos, found - 1)
		else
			line = string.sub(text, pos)
		end
		fontString:SetText(line)
		local lineWidth = tonumber(fontString:GetStringWidth()) or 0
		if lineWidth > width then width = lineWidth end
		if not found then break end
		pos = found + 1
	end
	fontString:SetText(text)
	return width
end

local function MeasureHeight(fontString, text, fontSize)
	local ok, height = pcall(fontString.GetHeight, fontString)
	height = ok and tonumber(height) or 0
	if height > 0 then return height end
	return fontSize * CountLines(text)
end

-- Sets the region's text from its aura's state and sizes the region to it.
-- A text that shows a time left keeps redrawing every frame.
function PA:RenderText(region)
	local data = region.data
	if not data then return end
	local auraState = self.auraStates[data.id]
	local text, ticking = self:FormatText(data.displayText, auraState, GetTime())
	-- Shown only as the options preview, a text with nothing to show shows
	-- its own placeholders, so it can be seen while it is edited.
	if not (auraState and auraState.active) and string.find(text, "^%s*$") then
		text = string.gsub(data.displayText or "", "\\n", "\n")
	end
	if text == "" then text = " " end

	if ticking ~= region.ticking then
		region.ticking = ticking
		region:SetScript("OnUpdate", ticking and region.tick or nil)
	end
	if text == region.shownText then return end

	local fontString = region.text
	local scale = region.scale or 1
	local fontSize = (data.fontSize or 12) * scale
	local width
	if data.automaticWidth == "Fixed" then
		width = (data.fixedWidth or 200) * scale
		fontString:SetWidth(width)
		fontString:SetText(text)
	else
		fontString:SetWidth(MEASURE_WIDTH)
		width = MeasureWidth(fontString, text)
	end
	local height = MeasureHeight(fontString, text, fontSize)
	if width < 1 then width = 1 end
	if height < 1 then height = 1 end

	region:SetWidth(width)
	region:SetHeight(height)
	local oldWidth, oldHeight = region.width, region.height
	region.width, region.height = width / scale, height / scale
	-- A hidden text may measure wrong: it is measured again once shown.
	if region:IsShown() then
		region.shownText = text
	else
		region.shownText = nil
	end
	if data.parent and (oldWidth ~= region.width or oldHeight ~= region.height) then
		self:LayoutGroup(data.parent)
	end
end

-- A grouped text is placed against its group, its font size and offsets
-- scaled by the group's scale (PA:GetRegionAnchor).
local function Modify(region, data)
	local anchor, scale = PA:GetRegionAnchor(data)
	region.data = data
	region.scale = scale
	region.shownText = nil

	local fontString = region.text
	PA:SetTextFont(fontString, data.font, (data.fontSize or 12) * scale, data.outline, true)

	local c = data.color or { 1, 1, 1, 1 }
	fontString:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
	local s = data.shadowColor or { 0, 0, 0, 1 }
	pcall(fontString.SetShadowColor, fontString, s[1] or 0, s[2] or 0, s[3] or 0, s[4] or 1)
	pcall(fontString.SetShadowOffset, fontString, data.shadowXOffset or 0, data.shadowYOffset or 0)
	pcall(fontString.SetNonSpaceWrap, fontString, true)

	local justify = data.justify or "LEFT"
	fontString:SetJustifyH(justify)
	fontString:ClearAllPoints()
	fontString:SetPoint(justify, region, justify, 0, 0)

	region:ClearAllPoints()
	region:SetPoint(data.selfPoint or "BOTTOM", anchor, data.anchorPoint or "CENTER",
		(data.xOffset or 0) * scale, (data.yOffset or 0) * scale)
	PA:RenderText(region)
end

-- Runs after every evaluation and once the region is shown: the text
-- follows the aura's state.
local function Progress(region, data)
	region.data = data
	PA:RenderText(region)
end

PA.regionTypes.text.create = Create
PA.regionTypes.text.modify = Modify
PA.regionTypes.text.progress = Progress
