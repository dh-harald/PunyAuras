-- The empty region (WeakAuras RegionTypes/Empty.lua, GPLv2): a frame that
-- draws nothing itself, only its sub-region texts. Its size is what the
-- texts are placed against and what a dynamic group lays it out by. Its
-- alpha reaches the texts through their colour (Regions/SubTexts.lua), as
-- the frame's SetAlpha does not carry over on Unreal Azeroth.

local PA = unpack(PunyAuras)

local function Create(parent)
	local region = CreateFrame("Frame", nil, parent)
	region:Hide()
	return region
end

-- A grouped empty region is placed against its group, its size and offsets
-- scaled by the group's scale (PA:GetRegionAnchor).
local function Modify(region, data)
	local anchor, scale = PA:GetRegionAnchor(data)
	region:SetWidth(data.width * scale)
	region:SetHeight(data.height * scale)
	region:ClearAllPoints()
	region:SetPoint(data.selfPoint or "CENTER", anchor, data.anchorPoint or "CENTER",
		(data.xOffset or 0) * scale, (data.yOffset or 0) * scale)
end

PA.regionTypes.empty.create = Create
PA.regionTypes.empty.modify = Modify
