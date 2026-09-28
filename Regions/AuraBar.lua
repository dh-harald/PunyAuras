-- The progress bar region (WeakAuras RegionTypes/AuraBar.lua, GPLv2): a bar
-- that shows its aura's progress, with an optional icon at one end.
--
-- Like WeakAuras' own bar it is not a StatusBar: a background texture and a
-- fill texture, the fill sized to the progress and cut with SetTexCoord to
-- the same part of the texture, so the texture is not stretched (Unreal
-- Azeroth's native StatusBar fill does not follow SetValue either). Every
-- texture belongs to the region frame itself, as hiding a frame does not
-- hide its child frames on Unreal Azeroth. Only the four-argument
-- SetTexCoord is used (the eight-argument form draws skewed there), so a
-- vertical bar shows its texture unrotated.
--
-- Orientation, as WeakAuras names it by the direction the bar empties in:
-- HORIZONTAL "Right to Left" (fill held at the left end), HORIZONTAL_INVERSE
-- "Left to Right" (right end), VERTICAL "Bottom to Top" (top end),
-- VERTICAL_INVERSE "Top to Bottom" (bottom end).
--
-- Progress (PA:StateProgress): timed, the time left of the duration, redrawn
-- every frame while shown; static, value of total; `inverse` flips either.
-- A bar without a progress -- most auras on the 1.12.1 client report no
-- time -- is full, where WeakAuras draws it empty: an active aura with an
-- empty bar would look like no aura at all.

local PA = unpack(PunyAuras)

local LSM = LibStub("LibSharedMedia-3.0", true)
local DEFAULT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

-- The fill of a bar, 0 to 1, for a progress state (PA:StateProgress) at
-- time `now`.
function PA:BarProgress(progressState, inverse, now)
	if not progressState then return 1 end
	local progress
	if progressState.progressType == "timed" then
		local duration = tonumber(progressState.duration) or 0
		if duration <= 0 or not progressState.expirationTime then return 1 end
		progress = (progressState.expirationTime - now) / duration
	elseif progressState.progressType == "static" then
		local total = tonumber(progressState.total) or 0
		progress = total ~= 0 and (tonumber(progressState.value) or 0) / total or 0
	else
		return 1
	end
	if progress < 0 then progress = 0 end
	if progress > 1 then progress = 1 end
	if inverse then progress = 1 - progress end
	return progress
end

-- The texture of a LibSharedMedia statusbar name, falling back to the
-- default one.
local function BarTexture(name)
	local path = LSM and LSM:Fetch("statusbar", name or "", true)
	return path or DEFAULT_TEXTURE
end

-- Sizes and cuts the fill for `progress` (0 to 1). The fill's anchor, at the
-- end it is held at, is set by Modify.
local function SetBarProgress(region, progress)
	local fill = region.fill
	local width, height = region.barWidth or 0, region.barHeight or 0
	if progress <= 0 or width <= 0 or height <= 0 then
		fill:Hide()
		return
	end
	local orientation = region.orientation
	if orientation == "HORIZONTAL" then
		fill:SetWidth(width * progress)
		fill:SetHeight(height)
		fill:SetTexCoord(0, progress, 0, 1)
	elseif orientation == "HORIZONTAL_INVERSE" then
		fill:SetWidth(width * progress)
		fill:SetHeight(height)
		fill:SetTexCoord(1 - progress, 1, 0, 1)
	elseif orientation == "VERTICAL" then
		fill:SetWidth(width)
		fill:SetHeight(height * progress)
		fill:SetTexCoord(0, 1, 0, progress)
	else
		fill:SetWidth(width)
		fill:SetHeight(height * progress)
		fill:SetTexCoord(0, 1, 1 - progress, 1)
	end
	fill:Show()
end

local function Create(parent)
	local region = CreateFrame("Frame", nil, parent)
	region.background = region:CreateTexture(nil, "BACKGROUND")
	region.fill = region:CreateTexture(nil, "ARTWORK")
	region.icon = region:CreateTexture(nil, "ARTWORK")
	-- A timed progress is redrawn every frame; the closure keeps the region
	-- without relying on how the client passes the frame to OnUpdate.
	region.tick = function()
		SetBarProgress(region, PA:BarProgress(region.progressState, region.inverse, GetTime()))
	end
	region:Hide()
	return region
end

-- WeakAuras' zoom: the icon shows the middle part of its texture.
local function SetIconZoom(icon, zoom)
	local half = 0.5 * (1 - 0.5 * (zoom or 0))
	icon:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
end

local function SetColor(texture, color, alpha)
	local c = color or { 1, 1, 1, 1 }
	texture:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, (c[4] or 1) * alpha)
end

-- A grouped bar is placed against its group, its size and offsets scaled by
-- the group's scale (PA:GetRegionAnchor). Alpha goes into every texture's
-- colour: the frame's SetAlpha does not carry over on Unreal Azeroth.
local function Modify(region, data)
	local anchor, scale = PA:GetRegionAnchor(data)
	local width, height = data.width * scale, data.height * scale
	region:SetWidth(width)
	region:SetHeight(height)
	region:ClearAllPoints()
	region:SetPoint(data.selfPoint or "CENTER", anchor, data.anchorPoint or "CENTER",
		(data.xOffset or 0) * scale, (data.yOffset or 0) * scale)

	local alpha = data.alpha or 1
	local orientation = data.orientation or "HORIZONTAL"
	local horizontal = (orientation == "HORIZONTAL" or orientation == "HORIZONTAL_INVERSE")
	region.orientation = orientation
	region.inverse = data.inverse and true or false

	-- The icon is a square at one end: "LEFT" is the left or the top end,
	-- "RIGHT" the right or the bottom one; the bar takes the rest.
	-- The bar part and the icon are kept as insets from the frame's edges
	-- ({ left, right, top, bottom }, drawn pixels), which the sub-region
	-- texts are placed by (Regions/SubTexts.lua).
	local left, right, top, bottom = 0, 0, 0, 0
	local icon = region.icon
	region.iconInsets = nil
	if data.icon then
		local size = horizontal and height or width
		local first = (data.icon_side == "LEFT")
		local point
		if horizontal then
			point = first and "LEFT" or "RIGHT"
			if first then left = size else right = size end
			region.iconInsets = first and { 0, width - size, 0, 0 } or { width - size, 0, 0, 0 }
		else
			point = first and "TOP" or "BOTTOM"
			if first then top = size else bottom = size end
			region.iconInsets = first and { 0, 0, 0, height - size } or { 0, 0, height - size, 0 }
		end
		icon:ClearAllPoints()
		icon:SetPoint(point, region, point, 0, 0)
		icon:SetWidth(size)
		icon:SetHeight(size)
		icon:SetTexture(PA:GetAuraIcon(data))
		SetColor(icon, data.icon_color, alpha)
		pcall(icon.SetDesaturated, icon, data.desaturate and true or false)
		SetIconZoom(icon, data.zoom)
		icon:Show()
	else
		icon:Hide()
	end
	region.barWidth = width - left - right
	region.barHeight = height - top - bottom
	region.barInsets = { left, right, top, bottom }

	local texture = BarTexture(data.texture)
	local background = region.background
	background:ClearAllPoints()
	background:SetPoint("TOPLEFT", region, "TOPLEFT", left, -top)
	background:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", -right, bottom)
	background:SetTexture(texture)
	SetColor(background, data.backgroundColor, alpha)

	local fill = region.fill
	fill:SetTexture(texture)
	SetColor(fill, data.barColor, alpha)
	fill:ClearAllPoints()
	if orientation == "HORIZONTAL" or orientation == "VERTICAL" then
		fill:SetPoint("TOPLEFT", region, "TOPLEFT", left, -top)
	elseif orientation == "HORIZONTAL_INVERSE" then
		fill:SetPoint("TOPRIGHT", region, "TOPRIGHT", -right, -top)
	else
		fill:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", left, bottom)
	end
	SetBarProgress(region, PA:BarProgress(region.progressState, region.inverse, GetTime()))
end

-- Takes the aura's progress; a timed one keeps the bar moving every frame
-- while it is shown.
local function Progress(region, data, progressState)
	region.progressState = progressState
	region.inverse = data.inverse and true or false
	local timed = progressState ~= nil and progressState.progressType == "timed"
		and (tonumber(progressState.duration) or 0) > 0
	if timed ~= region.ticking then
		region.ticking = timed
		region:SetScript("OnUpdate", timed and region.tick or nil)
	end
	region.tick()
end

PA.regionTypes.aurabar.create = Create
PA.regionTypes.aurabar.modify = Modify
PA.regionTypes.aurabar.progress = Progress
