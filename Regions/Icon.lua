-- The icon region: an aura shown as a single texture, sized, placed and
-- tinted from its data (WeakAuras RegionTypes/Icon.lua, GPLv2). Its texts
-- are sub-region texts (Regions/SubTexts.lua); the cooldown overlay is not
-- part of it.

local PA = unpack(PunyAuras)

local function Create(parent)
	local region = CreateFrame("Frame", nil, parent)
	local icon = region:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(region)
	region.icon = icon
	region:Hide()
	return region
end

-- WeakAuras' UpdateTexCoords: zoom narrows the visible part of the texture
-- around its centre, keepAspectRatio crops it to the region's shape. Only
-- the four-argument SetTexCoord is used: the eight-argument form draws
-- skewed on Unreal Azeroth.
local function UpdateTexCoords(region, data)
	local texWidth = 1 - 0.5 * (data.zoom or 0)
	local aspectRatio = 1
	if data.keepAspectRatio and data.width > 0 and data.height > 0 then
		aspectRatio = data.width / data.height
	end
	local xRatio = aspectRatio < 1 and aspectRatio or 1
	local yRatio = aspectRatio > 1 and 1 / aspectRatio or 1

	local halfX = 0.5 * texWidth * xRatio
	local halfY = 0.5 * texWidth * yRatio
	region.icon:SetTexCoord(0.5 - halfX, 0.5 + halfX, 0.5 - halfY, 0.5 + halfY)
end

-- A grouped icon is placed against its group, its size and offsets scaled
-- by the group's scale (PA:GetRegionAnchor).
local function Modify(region, data)
	local anchor, scale = PA:GetRegionAnchor(data)
	region:SetWidth(data.width * scale)
	region:SetHeight(data.height * scale)
	region:ClearAllPoints()
	region:SetPoint(data.selfPoint or "CENTER", anchor, data.anchorPoint or "CENTER",
		(data.xOffset or 0) * scale, (data.yOffset or 0) * scale)

	local icon = region.icon
	icon:SetTexture(PA:GetAuraIcon(data))
	-- Alpha goes into the texture's own colour rather than the frame's
	-- SetAlpha, which does not carry over to children on Unreal Azeroth.
	local c = data.color or { 1, 1, 1, 1 }
	icon:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, (c[4] or 1) * (data.alpha or 1))
	pcall(icon.SetDesaturated, icon, data.desaturate and true or false)
	UpdateTexCoords(region, data)
end

PA.regionTypes.icon.create = Create
PA.regionTypes.icon.modify = Modify
