-- Regions: the on-screen frame of each aura, created by its region type
-- (PA.regionTypes[type].create) and brought up to date from its data
-- (.modify), keyed by aura id like WeakAuras' Private.regions.
--
-- A region is shown while its aura is active (Core/Triggers.lua), and the
-- aura picked in the options window is shown regardless while the window is
-- open, the way WeakAuras shows the aura being edited; a picked group shows
-- all of its children.
--
-- A group's region is an invisible anchor that stays shown; its children are
-- placed against it and shown or hidden one by one (on Unreal Azeroth hiding
-- a frame does not hide its children, so nothing relies on that). Every
-- region stays a child of UIParent: a group's scale is applied by each child
-- to its own size and offsets (PA:GetRegionAnchor) rather than with
-- SetScale, which is unreliable on Unreal Azeroth.
--
-- A region is drawn from its aura's data with the changes of the
-- conditions that hold on top (PA:GetRegionData, Core/Conditions.lua).
--
-- The region types that carry sub-region texts (PA.subTextRegionTypes) have
-- them applied after their own modify, and set from the aura's state with
-- the region's progress (Regions/SubTexts.lua).
--
-- A group type with a `layout` (the dynamic group) places its shown
-- children itself, after they were shown or hidden: PA:LayoutGroup runs
-- whenever one of its children is refreshed, and once after a refresh of
-- the whole group.

local PA = unpack(PunyAuras)
local Compat = PunyAuras.Compat

PA.regions = {}

-- Ids shown as the options preview: the picked aura, and a picked group's
-- children.
local preview = {}
-- Groups whose layout waits until all of their children were refreshed.
local layoutSuspended = {}

-- The frame a region is placed against and the scale it is drawn at: its
-- group's region and scale for a grouped aura (WeakAuras' Group Scale,
-- limited to 0-10 as there), the screen otherwise.
function PA:GetRegionAnchor(data)
	local group = data.parent and self:GetData(data.parent)
	local groupRegion = data.parent and self.regions[data.parent]
	if group and groupRegion then
		local scale = group.scale
		if not (scale and scale > 0 and scale <= 10) then scale = 1 end
		return groupRegion, scale
	end
	return UIParent, 1
end

-- Creates the region of `id` if needed and applies its current data. A
-- grouped aura's group region is brought up to date first, as its anchor.
function PA:UpdateRegion(id)
	local data = self:GetRegionData(id)
	if not data then return end
	local typeInfo = self.regionTypes[data.regionType]
	if not (typeInfo and typeInfo.create) then return end

	if data.parent then self:UpdateRegion(data.parent) end

	local region = self.regions[id]
	if region and region.regionType ~= data.regionType then
		region:Hide()
		region = nil
	end
	if not region then
		region = typeInfo.create(UIParent)
		region.regionType = data.regionType
		self.regions[id] = region
	end
	typeInfo.modify(region, data)
	if self.subTextRegionTypes[data.regionType] then
		self:ModifySubTexts(region, data)
	end
	return region
end

-- Shows or hides the region of `id` for its aura's state and the preview,
-- re-applying its data when shown. A group re-applies its children too,
-- which follow its position and scale.
function PA:RefreshRegion(id)
	local data = self:GetData(id)
	if self:IsGroup(data) then
		local region = self:UpdateRegion(id)
		if region then region:Show() end
		layoutSuspended[id] = true
		local i
		for i = 1, Compat.getn(data.controlledChildren) do
			self:RefreshRegion(data.controlledChildren[i])
		end
		layoutSuspended[id] = nil
		self:LayoutGroup(id)
		return
	end

	if self:IsRegionWanted(id) then
		local region = self:UpdateRegion(id)
		if region then
			region:Show()
			self:UpdateRegionProgress(id)
		end
	elseif self.regions[id] then
		self.regions[id]:Hide()
	end
	if data and data.parent then self:LayoutGroup(data.parent) end
end

-- Hands a shown region whose type draws a progress (`progress`, the bar)
-- the trigger state its progress comes from (PA:StateProgress), and sets
-- its sub-region texts from its aura's state.
function PA:UpdateRegionProgress(id)
	local region = self.regions[id]
	if not (region and region:IsShown()) then return end
	local data = self:GetRegionData(id)
	local typeInfo = data and self.regionTypes[data.regionType]
	if typeInfo and typeInfo.progress then
		typeInfo.progress(region, data, self:StateProgress(self.auraStates[id]))
	end
	self:UpdateSubTexts(region)
end

-- Whether the region of `id` is to be shown: its aura is active, or it is
-- part of the options preview.
function PA:IsRegionWanted(id)
	local state = self.auraStates[id]
	return preview[id] or (state ~= nil and state.active)
end

-- When the aura's shown state runs out (GetTime() based), from its first
-- active trigger that has one; nil for an aura without a time left, which
-- only the player's own auras report.
local function ExpirationTime(state)
	if not state then return nil end
	local i
	for i = 1, Compat.getn(state.triggers) do
		local trigger = state.triggers[i]
		if trigger.active and trigger.expirationTime then
			return trigger.expirationTime
		end
	end
end

-- Hands a group type with a `layout` its shown children, in the group's
-- order: { id, index, data, region, expirationTime, width, height } each.
-- The size is unscaled: the data's, or for a region sized by its content
-- (the text) the region's own `width` / `height`.
function PA:LayoutGroup(groupId)
	if layoutSuspended[groupId] then return end
	local data = self:GetData(groupId)
	local typeInfo = data and self.regionTypes[data.regionType]
	local region = self.regions[groupId]
	if not (typeInfo and typeInfo.layout and region) then return end

	local shown = {}
	local i
	for i = 1, Compat.getn(data.controlledChildren) do
		local childId = data.controlledChildren[i]
		local childRegion = self.regions[childId]
		if childRegion and self:IsRegionWanted(childId) then
			local childData = self:GetRegionData(childId)
			table.insert(shown, {
				id = childId,
				index = i,
				data = childData,
				region = childRegion,
				expirationTime = ExpirationTime(self.auraStates[childId]),
				width = childRegion.width or childData.width or 0,
				height = childRegion.height or childData.height or 0,
			})
		end
	end
	typeInfo.layout(region, data, shown)
end

-- Shows `id` as the options preview (nil ends the preview); a group is
-- previewed with all of its children.
function PA:SetPreview(id)
	local old = preview
	preview = {}
	local data = id and self:GetData(id)
	if data then
		preview[id] = true
		if self:IsGroup(data) then
			local i
			for i = 1, Compat.getn(data.controlledChildren) do
				preview[data.controlledChildren[i]] = true
			end
		end
	end

	local oldId
	for oldId in pairs(old) do
		if not preview[oldId] then self:RefreshRegion(oldId) end
	end
	if data then self:RefreshRegion(id) end
end

-- Keeps a region with its aura when the aura is renamed.
function PA:RenameRegion(oldId, newId)
	self.regions[newId] = self.regions[oldId]
	self.regions[oldId] = nil
	self.auraStates[newId] = self.auraStates[oldId]
	self.auraStates[oldId] = nil
	self.loaded[newId] = self.loaded[oldId]
	self.loaded[oldId] = nil
	if preview[oldId] then
		preview[oldId] = nil
		preview[newId] = true
	end
end

-- Hides a deleted aura's region. The frame itself cannot be destroyed; it
-- is dropped from the table and never shown again.
function PA:ReleaseRegion(id)
	local region = self.regions[id]
	if region then region:Hide() end
	self.regions[id] = nil
	self.auraStates[id] = nil
	self.loaded[id] = nil
	preview[id] = nil
end
