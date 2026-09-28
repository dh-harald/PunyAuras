-- The texture region (WeakAuras RegionTypes/Texture.lua, GPLv2): one texture,
-- sized, placed, tinted and optionally mirrored.
--
-- WeakAuras' rotation needs the eight-argument SetTexCoord, which draws
-- skewed on Unreal Azeroth, or Texture:SetRotation, which the 1.12.1 client
-- lacks, and its blend modes other than BLEND draw differently on Unreal
-- Azeroth: neither is part of this region. Mirroring is the four-argument
-- SetTexCoord with its left and right swapped.

local PA = unpack(PunyAuras)

local function Create(parent)
	local region = CreateFrame("Frame", nil, parent)
	local texture = region:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints(region)
	region.texture = texture
	region:Hide()
	return region
end

-- A grouped texture is placed against its group, its size and offsets
-- scaled by the group's scale (PA:GetRegionAnchor). Alpha goes into the
-- texture's colour: the frame's SetAlpha does not carry over on Unreal
-- Azeroth.
local function Modify(region, data)
	local anchor, scale = PA:GetRegionAnchor(data)
	region:SetWidth(data.width * scale)
	region:SetHeight(data.height * scale)
	region:ClearAllPoints()
	region:SetPoint(data.selfPoint or "CENTER", anchor, data.anchorPoint or "CENTER",
		(data.xOffset or 0) * scale, (data.yOffset or 0) * scale)

	local texture = region.texture
	texture:SetTexture(data.texture or PA.DEFAULT_AURA_TEXTURE)
	local c = data.color or { 1, 1, 1, 1 }
	texture:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, (c[4] or 1) * (data.alpha or 1))
	pcall(texture.SetDesaturated, texture, data.desaturate and true or false)
	if data.mirror then
		texture:SetTexCoord(1, 0, 0, 1)
	else
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

PA.regionTypes.texture.create = Create
PA.regionTypes.texture.modify = Modify
