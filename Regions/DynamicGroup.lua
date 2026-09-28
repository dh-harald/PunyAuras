-- The dynamic group region (WeakAuras RegionTypes/DynamicGroup.lua, GPLv2):
-- an invisible 2x2 anchor, like the static group's, that places its shown
-- children one after the other, without gaps (PA:LayoutGroup hands them
-- over whenever one of them is shown or hidden).
--
-- The layout ports WeakAuras' growers LEFT, RIGHT, UP, DOWN, HORIZONTAL and
-- VERTICAL, without stagger and anchor-per-unit: every shown child gets an
-- x, y offset from the group's anchor and is placed by the group's
-- selfPoint (PA:DynamicGroupSelfPoint) against the anchor's centre. The
-- centred rows go in WeakAuras' default "LR" order: the first child at the
-- left, or for VERTICAL at the bottom.
--
-- Sorting ports WeakAuras' sorters "none" (the group's order), "ascending"
-- and "descending" (by expiration time). Auras without one come first
-- when ascending and last when descending, as WeakAuras' SortNilFirst puts
-- them; ties keep the group's order. Children past the limit are hidden.
--
-- Sizes, offsets and spacing are scaled by the group's scale, as in the
-- static group (PA:GetRegionAnchor).

local PA = unpack(PunyAuras)
local Compat = PunyAuras.Compat

-- WeakAurasOptions RegionOptions/DynamicGroup.lua `selfPoints`, by grow
-- and align.
local SELF_POINTS = {
	RIGHT = { LEFT = "TOPLEFT", RIGHT = "BOTTOMLEFT", CENTER = "LEFT" },
	LEFT = { LEFT = "TOPRIGHT", RIGHT = "BOTTOMRIGHT", CENTER = "RIGHT" },
	UP = { LEFT = "BOTTOMLEFT", RIGHT = "BOTTOMRIGHT", CENTER = "BOTTOM" },
	DOWN = { LEFT = "TOPLEFT", RIGHT = "TOPRIGHT", CENTER = "TOP" },
	HORIZONTAL = { LEFT = "TOP", RIGHT = "BOTTOM", CENTER = "CENTER" },
	VERTICAL = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" },
}

-- The point every child of a dynamic group is placed by.
function PA:DynamicGroupSelfPoint(data)
	local points = SELF_POINTS[data.grow]
	if not points then return "CENTER" end
	return points[data.align] or points.CENTER
end

-- Whether shown child `a` comes before `b`, sorting by expiration time.
local function SortsBefore(a, b, descending)
	local ta, tb = a.expirationTime, b.expirationTime
	if ta == nil and tb ~= nil then return not descending end
	if tb == nil and ta ~= nil then return descending end
	if ta ~= nil and math.abs(ta - tb) >= 0.001 then
		if descending then return ta > tb end
		return ta < tb
	end
	return a.index < b.index
end

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

-- Places `shown` ({ index, data, region, expirationTime, width, height } per
-- child, in the group's order; PA:LayoutGroup).
local function Layout(region, data, shown)
	local scale = data.scale
	if not (scale and scale > 0 and scale <= 10) then scale = 1 end
	local space = (data.space or 0) * scale

	if data.sort == "ascending" or data.sort == "descending" then
		local descending = (data.sort == "descending")
		table.sort(shown, function(a, b) return SortsBefore(a, b, descending) end)
	end

	local count = Compat.getn(shown)
	local visible = count
	if data.useLimit then
		visible = math.max(math.min(count, math.floor(tonumber(data.limit) or 0)), 0)
	end

	local grow = data.grow
	local centred = (grow == "HORIZONTAL" or grow == "VERTICAL")
	local pos = 0
	local i
	if centred then
		local total = math.max(visible - 1, 0) * space
		for i = 1, visible do
			if grow == "HORIZONTAL" then
				total = total + shown[i].width * scale
			else
				total = total + shown[i].height * scale
			end
		end
		pos = -total / 2
	end

	local selfPoint = PA:DynamicGroupSelfPoint(data)
	for i = 1, count do
		local entry = shown[i]
		if i > visible then
			entry.region:Hide()
		else
			local width = entry.width * scale
			local height = entry.height * scale
			local x, y = 0, 0
			if grow == "LEFT" then
				x = pos
				pos = pos - width - space
			elseif grow == "RIGHT" then
				x = pos
				pos = pos + width + space
			elseif grow == "UP" then
				y = pos
				pos = pos + height + space
			elseif grow == "HORIZONTAL" then
				x = pos + width / 2
				pos = pos + width + space
			elseif grow == "VERTICAL" then
				y = pos + height / 2
				pos = pos + height + space
			else
				y = pos
				pos = pos - height - space
			end
			entry.region:ClearAllPoints()
			entry.region:SetPoint(selfPoint, region, "CENTER", x, y)
		end
	end
end

PA.regionTypes.dynamicgroup.create = Create
PA.regionTypes.dynamicgroup.modify = Modify
PA.regionTypes.dynamicgroup.layout = Layout
