-- Sub-region texts (WeakAuras SubRegionTypes/SubText.lua, GPLv2): the texts
-- an icon, bar, texture or progress texture carries in `data.subRegions`
-- (entries of type "subtext"; entries of other types are left alone), with
-- the placeholders of Regions/Texts.lua.
--
-- Every text is a font string of the region frame itself, not a child
-- frame of it: hiding a frame does not hide its child frames on Unreal
-- Azeroth. A region keeps the font strings it once made (a font string
-- cannot be destroyed) and hides the ones not in use.
--
-- Placement, as WeakAuras' AnchorSubRegion does it, but every point taken
-- against the region frame itself (no inner / outer frames, no anchoring to
-- a texture that may be hidden):
--   * icon: the edge points and the centre; "INNER_" points of the frame
--     shrunk by 10% of its size on each side, "OUTER_" points of the frame
--     grown by 5% on each side.
--   * bar: the points of the bar part (the frame without the icon),
--     "INNER_" ones 2 pixels inside it, "ICON_" ones of the icon (of the
--     bar part while the icon is not shown).
--   * texture, progress texture: the frame's points.
-- The "Automatic" anchor (text_selfPoint "AUTO") is WeakAuras': an icon's
-- inner text is anchored at the same point, an outer one at the opposite
-- point, the centre and the edges at its centre; a bar's at the same point;
-- a texture's at the opposite point. Group scale multiplies the size, the
-- offsets and the font size (PA:GetRegionAnchor).
--
-- A text's height is left to the client (SetTextHeight is not used: on
-- Unreal Azeroth it sets the height, holding the text to one line).
--
-- A text of automatic width stays MEASURE_WIDTH wide, justified to the
-- horizontal side of its anchor, the way the text region does it: a font
-- string held to its measured width wraps. Its lines therefore line up on
-- that side; the justify setting applies to a text of fixed width.
--
-- The texts follow the aura's state after every evaluation
-- (PA:UpdateRegionProgress); a text showing a time left is redrawn every
-- frame by one shared ticker while its region is shown.

local PA = unpack(PunyAuras)
local Compat = PunyAuras.Compat

-- A width no text reaches: the width of a text of automatic width.
local MEASURE_WIDTH = 10000

-- WeakAuras' Private.point_types and inverse_point_types.
local POINTS = {
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true, RIGHT = true,
	TOPRIGHT = true, TOP = true, TOPLEFT = true, LEFT = true, CENTER = true,
}
local INVERSE_POINTS = {
	BOTTOMLEFT = "TOPRIGHT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPLEFT",
	RIGHT = "LEFT", TOPRIGHT = "BOTTOMLEFT", TOP = "BOTTOM",
	TOPLEFT = "BOTTOMRIGHT", LEFT = "RIGHT", CENTER = "CENTER",
}

local function ValidPoint(point)
	if POINTS[point or ""] then return point end
	return "CENTER"
end

-- `point` without `prefix`, or nil when it does not start with it.
local function StripPrefix(point, prefix)
	local length = string.len(prefix)
	if string.sub(point, 1, length) == prefix then
		return string.sub(point, length + 1)
	end
end

-- The horizontal (-1 left, 1 right, 0 centre) and vertical (1 top,
-- -1 bottom, 0 centre) side of a point.
local function PointSides(point)
	local x, y = 0, 0
	if string.find(point, "LEFT", 1, true) then
		x = -1
	elseif string.find(point, "RIGHT", 1, true) then
		x = 1
	end
	if string.find(point, "TOP", 1, true) then
		y = 1
	elseif string.find(point, "BOTTOM", 1, true) then
		y = -1
	end
	return x, y
end

-- The offset of `point` of a rectangle inset into the frame by `insets`
-- ({ left, right, top, bottom }), from the same point of the frame.
local function InsetPoint(point, insets)
	local left, right, top, bottom = insets[1], insets[2], insets[3], insets[4]
	local sideX, sideY = PointSides(point)
	local x, y
	if sideX < 0 then
		x = left
	elseif sideX > 0 then
		x = -right
	else
		x = (left - right) / 2
	end
	if sideY > 0 then
		y = -top
	elseif sideY < 0 then
		y = bottom
	else
		y = (bottom - top) / 2
	end
	return x, y
end

-- WeakAuras' "Automatic" anchor of a text at `anchorPoint`.
local function AutoSelfPoint(regionType, anchorPoint)
	if regionType == "icon" then
		local inner = StripPrefix(anchorPoint, "INNER_")
		if inner then return ValidPoint(inner) end
		local outer = StripPrefix(anchorPoint, "OUTER_")
		if outer then return INVERSE_POINTS[outer] or "CENTER" end
		return "CENTER"
	elseif regionType == "aurabar" then
		local point = StripPrefix(anchorPoint, "ICON_") or StripPrefix(anchorPoint, "INNER_")
			or anchorPoint
		return ValidPoint(point)
	end
	return INVERSE_POINTS[anchorPoint] or "CENTER"
end

-- Where a text goes on its region: the point of the text (`selfPoint`), the
-- point of the region frame it is set to, and the offset from it, in drawn
-- pixels. `geometry` is the region as drawn: `width`, `height`, `scale`
-- (the group's), and for a bar `barInsets` (the bar part) and `iconInsets`
-- (the icon, nil without one) as { left, right, top, bottom } from the
-- frame's edges.
function PA:SubTextPlacement(regionType, sub, geometry)
	local anchorPoint = sub.anchor_point or "CENTER"
	local selfPoint = sub.text_selfPoint or "AUTO"
	if selfPoint == "AUTO" then
		selfPoint = AutoSelfPoint(regionType, anchorPoint)
	else
		selfPoint = ValidPoint(selfPoint)
	end

	local scale = geometry.scale or 1
	local x = (tonumber(sub.text_anchorXOffset) or 0) * scale
	local y = (tonumber(sub.text_anchorYOffset) or 0) * scale
	local point = anchorPoint
	local dx, dy = 0, 0

	if regionType == "icon" then
		local inner = StripPrefix(anchorPoint, "INNER_")
		local outer = StripPrefix(anchorPoint, "OUTER_")
		if inner or outer then
			point = ValidPoint(inner or outer)
			local sideX, sideY = PointSides(point)
			local factor = inner and -0.1 or 0.05
			dx = sideX * factor * geometry.width
			dy = sideY * factor * geometry.height
		else
			point = ValidPoint(anchorPoint)
		end
	elseif regionType == "aurabar" then
		local iconPoint = StripPrefix(anchorPoint, "ICON_")
		local inner = StripPrefix(anchorPoint, "INNER_")
		if iconPoint and geometry.iconInsets then
			point = ValidPoint(iconPoint)
			dx, dy = InsetPoint(point, geometry.iconInsets)
		else
			point = ValidPoint(iconPoint or inner or anchorPoint)
			dx, dy = InsetPoint(point, geometry.barInsets or { 0, 0, 0, 0 })
			if inner then
				local sideX, sideY = PointSides(point)
				dx = dx - sideX * 2 * scale
				dy = dy - sideY * 2 * scale
			end
		end
	else
		point = ValidPoint(anchorPoint)
	end
	return selfPoint, point, x + dx, y + dy
end

-- The horizontal justification of a text of automatic width at `selfPoint`.
local function SideJustify(selfPoint)
	local sideX = PointSides(selfPoint)
	if sideX < 0 then return "LEFT" end
	if sideX > 0 then return "RIGHT" end
	return "CENTER"
end

-- Redrawing texts that show a time left ---------------------------------------

-- Regions whose texts show a time left, redrawn every frame while shown.
local tickingRegions = {}
local ticker

local function RenderTexts(region, now)
	local data = region.subTextData
	if not data then return false end
	local auraState = PA.auraStates[data.id]
	local active = auraState ~= nil and auraState.active
	local ticking = false
	local i
	for i = 1, Compat.getn(region.subTexts) do
		local entry = region.subTexts[i]
		if entry.sub then
			local text, timed = PA:FormatText(entry.sub.text_text, auraState, now)
			if timed then ticking = true end
			-- Shown only as the options preview, a text with nothing to
			-- show shows its own placeholders, so it can be seen while it is
			-- edited.
			if not active and string.find(text, "^%s*$") then
				text = string.gsub(entry.sub.text_text or "", "\\n", "\n")
			end
			if text ~= entry.shownText then
				entry.shownText = text
				entry.fontString:SetText(text)
			end
		end
	end
	return ticking
end

local function Tick()
	local now = GetTime()
	local region
	for region in pairs(tickingRegions) do
		if Compat.bool(region:IsShown()) then
			RenderTexts(region, now)
		else
			tickingRegions[region] = nil
		end
	end
	if next(tickingRegions) == nil then
		ticker:SetScript("OnUpdate", nil)
	end
end

local function SetTicking(region, ticking)
	if ticking then
		tickingRegions[region] = true
		if not ticker then ticker = CreateFrame("Frame") end
		ticker:SetScript("OnUpdate", Tick)
	else
		tickingRegions[region] = nil
	end
end

-- Sets the texts of `region` from its aura's state.
function PA:UpdateSubTexts(region)
	if not region.subTexts then return end
	SetTicking(region, RenderTexts(region, GetTime()))
end

-- Building the texts -----------------------------------------------------------

-- The region as drawn, for PA:SubTextPlacement.
local function Geometry(region, data, scale)
	return {
		width = (data.width or 0) * scale,
		height = (data.height or 0) * scale,
		scale = scale,
		barInsets = region.barInsets,
		iconInsets = region.iconInsets,
	}
end

local function SetupText(region, fontString, sub, data, geometry)
	local scale = geometry.scale
	PA:SetTextFont(fontString, sub.text_font, (tonumber(sub.text_fontSize) or 12) * scale,
		sub.text_fontType)

	local c = sub.text_color or { 1, 1, 1, 1 }
	fontString:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, (c[4] or 1) * (data.alpha or 1))
	local s = sub.text_shadowColor or { 0, 0, 0, 1 }
	pcall(fontString.SetShadowColor, fontString, s[1] or 0, s[2] or 0, s[3] or 0, s[4] or 1)
	pcall(fontString.SetShadowOffset, fontString, sub.text_shadowXOffset or 0,
		sub.text_shadowYOffset or 0)
	-- Lines break at spaces only: with non-space wrap on, Unreal Azeroth
	-- breaks them at any character, inside words too.
	pcall(fontString.SetNonSpaceWrap, fontString, false)

	local selfPoint, point, x, y = PA:SubTextPlacement(data.regionType, sub, geometry)
	if sub.text_automaticWidth == "Fixed" then
		fontString:SetWidth((tonumber(sub.text_fixedWidth) or 64) * scale)
		fontString:SetJustifyH(sub.text_justify or "CENTER")
	else
		fontString:SetWidth(MEASURE_WIDTH)
		fontString:SetJustifyH(SideJustify(selfPoint))
	end
	fontString:ClearAllPoints()
	fontString:SetPoint(selfPoint, region, point, x, y)

	if sub.text_visible == false then
		fontString:Hide()
	else
		fontString:Show()
	end
end

-- Applies the sub-region texts of `data` to its region, after the region
-- type's own modify: one font string per "subtext" entry, the unused ones
-- hidden.
function PA:ModifySubTexts(region, data)
	region.subTexts = region.subTexts or {}
	region.subTextData = data
	local _, scale = self:GetRegionAnchor(data)
	local geometry = Geometry(region, data, scale)

	local used = 0
	local subRegions = data.subRegions or {}
	local i
	for i = 1, Compat.getn(subRegions) do
		local sub = subRegions[i]
		if type(sub) == "table" and sub.type == "subtext" then
			used = used + 1
			local entry = region.subTexts[used]
			if not entry then
				entry = { fontString = region:CreateFontString(nil, "OVERLAY", "GameFontHighlight") }
				region.subTexts[used] = entry
			end
			entry.sub = sub
			entry.shownText = nil
			SetupText(region, entry.fontString, sub, data, geometry)
		end
	end
	for i = used + 1, Compat.getn(region.subTexts) do
		local entry = region.subTexts[i]
		entry.sub = nil
		entry.shownText = nil
		entry.fontString:Hide()
	end
	self:UpdateSubTexts(region)
end
