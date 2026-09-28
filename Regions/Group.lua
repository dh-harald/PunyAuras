-- The group region: an invisible 2x2 anchor at the group's position, which
-- its children are placed against (WeakAuras RegionTypes/Group.lua, GPLv2;
-- its self point is CENTER there too). The group's scale is not applied here
-- but by each child (PA:GetRegionAnchor), and the group's own offsets are
-- unscaled: WeakAuras scales them with the frame and compensates when the
-- scale changes, which leaves the group's anchor where it was either way.

local PA = unpack(PunyAuras)

local function Create(parent)
	local region = CreateFrame("Frame", nil, parent)
	region:SetWidth(2)
	region:SetHeight(2)
	region:Hide()
	return region
end

local function Modify(region, data)
	region:ClearAllPoints()
	region:SetPoint("CENTER", UIParent, data.anchorPoint or "CENTER",
		data.xOffset or 0, data.yOffset or 0)
	region:Show()
end

PA.regionTypes.group.create = Create
PA.regionTypes.group.modify = Modify
