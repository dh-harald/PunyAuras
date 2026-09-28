-- The progress texture region (WeakAuras RegionTypes/ProgressTexture.lua and
-- BaseRegions/LinearProgressTexture.lua, GPLv2), its linear orientations: a
-- background texture and a foreground that shows the part of its texture
-- the progress covers.
--
-- The foreground is cut with the four-argument SetTexCoord and sized to the
-- part it shows, as the progress bar does (Regions/AuraBar.lua); WeakAuras'
-- circular orientations and its rotation need the eight-argument form,
-- which draws skewed on Unreal Azeroth, and are not part of this region.
--
-- Orientation, as WeakAuras' LinearProgressTexture draws it: HORIZONTAL
-- shows the texture from its left edge, held at the left; HORIZONTAL_INVERSE
-- from the right edge, held at the right; VERTICAL from the bottom, held at
-- the bottom; VERTICAL_INVERSE from the top, held at the top. `compress`
-- squeezes the whole texture into the shown part instead of cutting it;
-- `inverse` flips the progress; `mirror` flips both textures left to right.
-- The background is the whole texture, `backgroundOffset` pixels larger on
-- every side.
--
-- Progress comes as for the bar (PA:StateProgress, PA:BarProgress): a timed
-- one is redrawn every frame while shown, and an aura without a progress
-- shows the whole foreground.

local PA = unpack(PunyAuras)

-- Texture coordinates of the part [from, to] of the texture along x, with
-- `mirror` flipping them.
local function XCoords(from, to, mirror)
	if mirror then return 1 - from, 1 - to end
	return from, to
end

-- Sizes, places and cuts the foreground for `progress` (0 to 1).
local function SetForeground(region, progress)
	local foreground = region.foreground
	local width, height = region.fullWidth or 0, region.fullHeight or 0
	if progress <= 0 or width <= 0 or height <= 0 then
		foreground:Hide()
		return
	end
	local orientation = region.orientation
	local mirror = region.mirror
	local left, right, top, bottom = 0, 1, 0, 1
	if orientation == "HORIZONTAL" or orientation == "HORIZONTAL_INVERSE" then
		foreground:SetWidth(width * progress)
		foreground:SetHeight(height)
		if not region.compress then
			if orientation == "HORIZONTAL" then
				left, right = 0, progress
			else
				left, right = 1 - progress, 1
			end
		end
	else
		foreground:SetWidth(width)
		foreground:SetHeight(height * progress)
		if not region.compress then
			if orientation == "VERTICAL" then
				top, bottom = 1 - progress, 1
			else
				top, bottom = 0, progress
			end
		end
	end
	left, right = XCoords(left, right, mirror)
	foreground:SetTexCoord(left, right, top, bottom)
	foreground:Show()
end

-- The side the foreground is held at, for each orientation.
local ANCHORS = {
	HORIZONTAL = "LEFT",
	HORIZONTAL_INVERSE = "RIGHT",
	VERTICAL = "BOTTOM",
	VERTICAL_INVERSE = "TOP",
}

local function Create(parent)
	local region = CreateFrame("Frame", nil, parent)
	region.background = region:CreateTexture(nil, "BACKGROUND")
	region.foreground = region:CreateTexture(nil, "ARTWORK")
	region.tick = function()
		SetForeground(region, PA:BarProgress(region.progressState, region.inverse, GetTime()))
	end
	region:Hide()
	return region
end

local function SetColor(texture, color, alpha)
	local c = color or { 1, 1, 1, 1 }
	texture:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, (c[4] or 1) * alpha)
end

-- A grouped progress texture is placed against its group, its size, offsets
-- and background offset scaled by the group's scale (PA:GetRegionAnchor).
-- Alpha goes into every texture's colour: the frame's SetAlpha does not
-- carry over on Unreal Azeroth.
local function Modify(region, data)
	local anchor, scale = PA:GetRegionAnchor(data)
	local width, height = data.width * scale, data.height * scale
	region:SetWidth(width)
	region:SetHeight(height)
	region:ClearAllPoints()
	region:SetPoint(data.selfPoint or "CENTER", anchor, data.anchorPoint or "CENTER",
		(data.xOffset or 0) * scale, (data.yOffset or 0) * scale)

	local orientation = ANCHORS[data.orientation or ""] and data.orientation or "VERTICAL"
	region.orientation = orientation
	region.compress = data.compress and true or false
	region.mirror = data.mirror and true or false
	region.inverse = data.inverse and true or false
	region.fullWidth, region.fullHeight = width, height
	local alpha = data.alpha or 1

	local foregroundTexture = data.foregroundTexture or PA.DEFAULT_AURA_TEXTURE
	local backgroundTexture = foregroundTexture
	if not data.sameTexture then
		backgroundTexture = data.backgroundTexture or PA.DEFAULT_AURA_TEXTURE
	end

	local offset = (data.backgroundOffset or 0) * scale
	local background = region.background
	background:ClearAllPoints()
	background:SetPoint("TOPLEFT", region, "TOPLEFT", -offset, offset)
	background:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", offset, -offset)
	background:SetTexture(backgroundTexture)
	SetColor(background, data.backgroundColor, alpha)
	pcall(background.SetDesaturated, background, data.desaturateBackground and true or false)
	local left, right = XCoords(0, 1, region.mirror)
	background:SetTexCoord(left, right, 0, 1)

	local foreground = region.foreground
	foreground:SetTexture(foregroundTexture)
	SetColor(foreground, data.foregroundColor, alpha)
	pcall(foreground.SetDesaturated, foreground, data.desaturateForeground and true or false)
	local point = ANCHORS[orientation]
	foreground:ClearAllPoints()
	foreground:SetPoint(point, region, point, 0, 0)
	SetForeground(region, PA:BarProgress(region.progressState, region.inverse, GetTime()))
end

-- Takes the aura's progress; a timed one keeps the foreground moving every
-- frame while it is shown.
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

PA.regionTypes.progresstexture.create = Create
PA.regionTypes.progresstexture.modify = Modify
PA.regionTypes.progresstexture.progress = Progress
