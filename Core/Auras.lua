-- Aura data: storage, defaults and creation.
--
-- Mirrors WeakAuras' data model: every aura ("display") is one table in an
-- account-wide store keyed by its unique id (WeakAurasSaved.displays there,
-- PA.db.global.displays here), holding `id`, `regionType` and the region
-- type's own settings, filled in from that type's defaults on creation
-- (WeakAuras.NewAura, WeakAurasOptions/WeakAurasOptions.lua).
--
-- Groups: a group aura holds its children's ids, in order, in
-- `controlledChildren`, and every child names its group in `parent`, as in
-- WeakAuras. Unlike WeakAuras, groups do not nest: a child is never a group
-- itself. A group has no triggers and no load conditions of its own.

local PA, L, P, G = unpack(PunyAuras)
local Compat = PunyAuras.Compat

G.displays = {}

-- The textures the texture and progress texture regions offer (the texture
-- picker), a selection of WeakAuras' PowerAurasMedia and Media/Textures
-- under WeakAuras' names, re-encoded by scripts/make-textures.py into
-- Media/Textures/Auras. `file` is the file name without its extension. The
-- names are not localized, as in WeakAuras' texture_types; they are ASCII,
-- as the clients' fonts may lack other characters.
PA.AURA_TEXTURE_PATH = "Interface\\AddOns\\PunyAuras\\Media\\Textures\\Auras\\"
PA.auraTextures = {
	{ file = "PunyAurasAura1", name = "Runed Text" },
	{ file = "PunyAurasAura2", name = "Runed Text On Ring" },
	{ file = "PunyAurasAura3", name = "Power Waves" },
	{ file = "PunyAurasAura4", name = "Majesty" },
	{ file = "PunyAurasAura7", name = "Triangular Highlights" },
	{ file = "PunyAurasAura11", name = "Oblong Highlights" },
	{ file = "PunyAurasAura17", name = "Crescent Highlights" },
	{ file = "PunyAurasAura24", name = "Smoke" },
	{ file = "PunyAurasAura8", name = "Rune" },
	{ file = "PunyAurasAura10", name = "Skull and Crossbones" },
	{ file = "PunyAurasAura12", name = "Snowflake" },
	{ file = "PunyAurasAura13", name = "Flame" },
	{ file = "PunyAurasAura14", name = "Holy Rune" },
	{ file = "PunyAurasAura15", name = "Zig-Zag Exclamation Point" },
	{ file = "PunyAurasAura19", name = "Crossed Swords" },
	{ file = "PunyAurasAura21", name = "Shield" },
	{ file = "PunyAurasAura22", name = "Glow" },
	{ file = "PunyAurasAura26", name = "Droplet" },
	{ file = "PunyAurasAura27", name = "Alert" },
	{ file = "PunyAurasAura29", name = "Paw" },
	{ file = "PunyAurasAura45", name = "Circular Glow" },
	{ file = "PunyAurasAura53", name = "Exclamation Point" },
	{ file = "PunyAurasAura72", name = "Circle" },
	{ file = "PunyAurasAura73", name = "Ring" },
	{ file = "PunyAurasAura78", name = "Check" },
	{ file = "PunyAurasAura118", name = "X" },
	{ file = "PunyAurasAura42", name = "Dispel" },
	{ file = "PunyAurasAura43", name = "Danger" },
	{ file = "PunyAurasAura44", name = "Buff" },
	{ file = "PunyAurasCircle_Smooth", name = "Smooth Circle" },
	{ file = "PunyAurasCircle_Smooth_Border", name = "Smooth Circle with Border" },
	{ file = "PunyAurasCircle_White", name = "Circle" },
	{ file = "PunyAurasCircle_White_Border", name = "Circle with Border" },
	{ file = "PunyAurasSquare_Smooth", name = "Smooth Square" },
	{ file = "PunyAurasSquare_Smooth_Border", name = "Smooth Square with Border" },
	{ file = "PunyAurasSquare_White", name = "Square" },
	{ file = "PunyAurasSquare_White_Border", name = "Square with Border" },
	{ file = "PunyAurasSquare_FullWhite", name = "Full White Square" },
	{ file = "PunyAurasRing_10px", name = "Ring 10px" },
	{ file = "PunyAurasRing_20px", name = "Ring 20px" },
	{ file = "PunyAurasTriangle45", name = "45 Degree Triangle" },
	{ file = "PunyAurasSquare_Border_5px", name = "Square Border 5px" },
}
-- WeakAuras' default texture, PowerAuras "Power Waves".
PA.DEFAULT_AURA_TEXTURE = PA.AURA_TEXTURE_PATH .. "PunyAurasAura3"
-- The text region's icon in the list and the New view.
PA.TEXT_ICON = "Interface\\AddOns\\PunyAuras\\Media\\Textures\\PunyAurasText"
-- The model region's icon in the list and the New view.
PA.MODEL_ICON = "Interface\\Icons\\Spell_Holy_HolyBolt"

-- Region types with their defaults, as in WeakAuras' RegionTypes/*.lua.
PA.regionTypes = {
	-- WeakAuras RegionTypes/Icon.lua `default`, with `alpha` from
	-- regionPrototype.AddAlphaToDefault and `displayIcon` for a manually
	-- chosen icon (iconSource 0).
	icon = {
		default = {
			icon = true,
			desaturate = false,
			iconSource = -1,
			displayIcon = "",
			inverse = false,
			width = 64,
			height = 64,
			color = { 1, 1, 1, 1 },
			alpha = 1,
			selfPoint = "CENTER",
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			zoom = 0,
			keepAspectRatio = false,
			frameStrata = 1,
			cooldown = true,
			cooldownTextDisabled = false,
			cooldownSwipe = true,
			cooldownEdge = false,
		},
	},
	-- WeakAuras RegionTypes/AuraBar.lua `default`, as far as its settings
	-- exist here (Regions/AuraBar.lua), with `alpha` from
	-- regionPrototype.AddAlphaToDefault. `texture` is a LibSharedMedia
	-- statusbar name.
	aurabar = {
		default = {
			icon = false,
			desaturate = false,
			iconSource = -1,
			displayIcon = "",
			texture = "Blizzard",
			width = 200,
			height = 15,
			orientation = "HORIZONTAL",
			inverse = false,
			barColor = { 1, 0, 0, 1 },
			backgroundColor = { 0, 0, 0, 0.5 },
			alpha = 1,
			selfPoint = "CENTER",
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			icon_side = "RIGHT",
			icon_color = { 1, 1, 1, 1 },
			frameStrata = 1,
			zoom = 0,
		},
	},
	-- WeakAuras RegionTypes/Text.lua `default`, without the custom text
	-- settings. `font` is a LibSharedMedia font name; `wordWrap` is kept for
	-- WeakAuras' data shape, but the 1.12.1 client always wraps a text of a
	-- fixed width (it has no SetWordWrap to elide it).
	text = {
		default = {
			displayText = "%p",
			outline = "OUTLINE",
			color = { 1, 1, 1, 1 },
			justify = "LEFT",
			selfPoint = "BOTTOM",
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			font = "Friz Quadrata TT",
			fontSize = 12,
			frameStrata = 1,
			automaticWidth = "Auto",
			fixedWidth = 200,
			wordWrap = "WordWrap",
			shadowColor = { 0, 0, 0, 1 },
			shadowXOffset = 1,
			shadowYOffset = -1,
		},
	},
	-- WeakAuras RegionTypes/Texture.lua `default`, as far as its settings
	-- exist here (Regions/Texture.lua), with `alpha` from
	-- regionPrototype.AddAlphaToDefault.
	texture = {
		default = {
			texture = PA.DEFAULT_AURA_TEXTURE,
			desaturate = false,
			width = 200,
			height = 200,
			color = { 1, 1, 1, 1 },
			mirror = false,
			alpha = 1,
			selfPoint = "CENTER",
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			frameStrata = 1,
		},
	},
	-- WeakAuras RegionTypes/ProgressTexture.lua `default`, the linear
	-- orientations' settings (Regions/ProgressTexture.lua), with `alpha`
	-- from regionPrototype.AddAlphaToDefault.
	progresstexture = {
		default = {
			foregroundTexture = PA.DEFAULT_AURA_TEXTURE,
			backgroundTexture = PA.DEFAULT_AURA_TEXTURE,
			desaturateBackground = false,
			desaturateForeground = false,
			sameTexture = true,
			compress = false,
			backgroundOffset = 2,
			width = 200,
			height = 200,
			orientation = "VERTICAL",
			inverse = false,
			foregroundColor = { 1, 1, 1, 1 },
			backgroundColor = { 0.5, 0.5, 0.5, 0.5 },
			mirror = false,
			alpha = 1,
			selfPoint = "CENTER",
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			frameStrata = 1,
		},
	},
	-- WeakAuras RegionTypes/Model.lua `default`, its SetPosition / SetFacing
	-- settings (`api` false). The model is a file path (`model_path`, as in
	-- the WeakAuras of the WotLK client), by default a model the 1.12.1
	-- client has, as WeakAuras' own default does not exist there.
	model = {
		default = {
			model_path = "Spells\\Holy_Missile_Low.mdx",
			model_x = 0,
			model_y = 0,
			model_z = 0,
			rotation = 0,
			sequence = 1,
			advance = false,
			width = 200,
			height = 200,
			selfPoint = "CENTER",
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			frameStrata = 1,
		},
	},
	-- WeakAuras RegionTypes/Group.lua `default`, without its border and
	-- backdrop settings. `groupIcon` (RegionOptions/Group.lua) is left out
	-- as there: unset, the list shows the default group icon.
	group = {
		default = {
			controlledChildren = {},
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			frameStrata = 1,
			scale = 1,
		},
	},
	-- WeakAuras RegionTypes/DynamicGroup.lua `default`, as far as its
	-- settings exist here (Regions/DynamicGroup.lua). `selfPoint` follows
	-- `grow` and `align` (PA:DynamicGroupSelfPoint).
	dynamicgroup = {
		default = {
			controlledChildren = {},
			grow = "DOWN",
			selfPoint = "TOP",
			align = "CENTER",
			space = 2,
			sort = "none",
			useLimit = false,
			limit = 5,
			anchorPoint = "CENTER",
			anchorFrameType = "SCREEN",
			xOffset = 0,
			yOffset = 0,
			frameStrata = 1,
			scale = 1,
		},
	},
}

-- Sub-region texts (WeakAuras SubRegionTypes/SubText.lua, GPLv2): the
-- region types that carry them (WeakAuras' `supports`), and an entry of
-- `data.subRegions` with the defaults of its region type (WeakAuras'
-- `default`: an icon's text is outlined without a shadow, the others'
-- shadowed without an outline). The offsets are the `text_anchorXOffset` /
-- `text_anchorYOffset` WeakAuras reads.
PA.subTextRegionTypes = { icon = true, aurabar = true, texture = true, progresstexture = true }

function PA:DefaultSubText(regionType)
	local icon = (regionType == "icon")
	local anchor = "BOTTOMLEFT"
	if icon then
		anchor = "CENTER"
	elseif regionType == "aurabar" then
		anchor = "INNER_RIGHT"
	end
	return {
		type = "subtext",
		text_text = icon and "%p" or "%n",
		text_color = { 1, 1, 1, 1 },
		text_font = "Friz Quadrata TT",
		text_fontSize = 12,
		text_fontType = icon and "OUTLINE" or "None",
		text_visible = true,
		text_justify = "CENTER",
		text_selfPoint = "AUTO",
		anchor_point = anchor,
		text_anchorXOffset = 0,
		text_anchorYOffset = 0,
		text_shadowColor = { 0, 0, 0, 1 },
		text_shadowXOffset = icon and 0 or 1,
		text_shadowYOffset = icon and 0 or -1,
		rotateText = "NONE",
		text_automaticWidth = "Auto",
		text_fixedWidth = 64,
		text_wordWrap = "WordWrap",
	}
end

-- The texts a new aura starts with (WeakAuras' addDefaultsForNewAura): an
-- icon's stacks at its inner bottom right corner, a bar's progress at its
-- inner left end and its name at the inner right end.
local function AddDefaultSubTexts(data)
	local function Add(fields)
		local text = PA:DefaultSubText(data.regionType)
		local key, value
		for key, value in pairs(fields) do
			text[key] = value
		end
		table.insert(data.subRegions, text)
	end
	if data.regionType == "icon" then
		Add({ text_text = "%s", anchor_point = "INNER_BOTTOMRIGHT" })
	elseif data.regionType == "aurabar" then
		Add({ text_text = "%p", anchor_point = "INNER_LEFT" })
		Add({ text_text = "%n", anchor_point = "INNER_RIGHT" })
	end
end

-- Fills in the missing fields of an aura's sub-region texts (an imported
-- WeakAuras aura's may lack some); entries of other types are kept as they
-- are.
local function ValidateSubRegions(data)
	if type(data.subRegions) ~= "table" then
		data.subRegions = {}
	end
	local i
	for i = 1, Compat.getn(data.subRegions) do
		local sub = data.subRegions[i]
		if type(sub) == "table" and sub.type == "subtext" then
			local key, value
			for key, value in pairs(PA:DefaultSubText(data.regionType)) do
				if sub[key] == nil then sub[key] = value end
			end
		end
	end
end

-- Icon shown for an aura that has no icon of its own yet.
PA.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- A group's icon while it has no groupIcon: WeakAuras' default group and
-- dynamic group icons, drawn as textures.
PA.DEFAULT_GROUP_ICON = "Interface\\AddOns\\PunyAuras\\Media\\Textures\\PunyAurasGroup"
PA.DEFAULT_DYNAMIC_GROUP_ICON = "Interface\\AddOns\\PunyAuras\\Media\\Textures\\PunyAurasDynamicGroup"

-- An icon path both clients draw. Unreal Azeroth reports icons as
-- "/Game/Interface/Icons/<name>_TEX", a form only that client knows; it
-- draws the 1.12.1 client's "Interface\Icons\<name>" as well, so manual
-- icons are kept, exported and imported in that form.
function PA:PortableIconPath(path)
	if type(path) ~= "string" then return path end
	local _, _, inner = string.find(path, "^/Game/(.+)_TEX$")
	if not inner then return path end
	return (string.gsub(inner, "/", "\\"))
end

-- Puts an aura's manual icon and texture fields into the portable form.
function PA:PortableIcons(data)
	data.displayIcon = self:PortableIconPath(data.displayIcon)
	data.groupIcon = self:PortableIconPath(data.groupIcon)
	data.texture = self:PortableIconPath(data.texture)
	data.foregroundTexture = self:PortableIconPath(data.foregroundTexture)
	data.backgroundTexture = self:PortableIconPath(data.backgroundTexture)
end

-- Whether `data` is a group (WeakAuras' display button IsGroup).
function PA:IsGroup(data)
	return data ~= nil and (data.regionType == "group" or data.regionType == "dynamicgroup")
end

local function IndexOf(list, value)
	local i
	for i = 1, Compat.getn(list) do
		if list[i] == value then return i end
	end
end

-- A new aura trigger, as WeakAuras' data_stub starts one: a buff on the
-- player. `type` names the trigger system ("aura2" is WeakAuras' aura
-- trigger); the other fields belong to it.
function PA:DefaultAuraTrigger()
	return {
		type = "aura2",
		unit = "player",
		debuffType = "HELPFUL",
		matchesShowOn = "showOnActive",
	}
end

-- Fills in what an aura's data needs beyond its region type's defaults,
-- like WeakAuras' validate against data_stub: at least one trigger, how the
-- triggers combine ("any" / "all"), and the load conditions' table
-- (Core/Load.lua), the sub-regions' list (ValidateSubRegions) and the
-- conditions' (Core/Conditions.lua), each with a check and changes, and the
-- actions' (Core/Actions.lua). A group
-- only needs its children's list. Manual icons are put into the portable
-- form (PA:PortableIconPath).
function PA:ValidateData(data)
	self:PortableIcons(data)
	if self:IsGroup(data) then
		if type(data.controlledChildren) ~= "table" then
			data.controlledChildren = {}
		end
		data.parent = nil
		return
	end
	if type(data.load) ~= "table" then
		data.load = {}
	end
	ValidateSubRegions(data)
	if type(data.conditions) ~= "table" then
		data.conditions = {}
	end
	local c
	for c = 1, Compat.getn(data.conditions) do
		local condition = data.conditions[c]
		if type(condition) ~= "table" then
			condition = {}
			data.conditions[c] = condition
		end
		if type(condition.check) ~= "table" then condition.check = {} end
		if type(condition.changes) ~= "table" then condition.changes = {} end
	end
	if type(data.actions) ~= "table" then
		data.actions = {}
	end
	local _, when
	for _, when in ipairs({ "init", "start", "finish" }) do
		if type(data.actions[when]) ~= "table" then data.actions[when] = {} end
	end
	local triggers = data.triggers
	if type(triggers) ~= "table" then
		triggers = {}
		data.triggers = triggers
	end
	if not triggers[1] then
		triggers[1] = { trigger = self:DefaultAuraTrigger() }
	end
	triggers.disjunctive = triggers.disjunctive or "any"
end

-- Group membership is kept on both sides; the groups' lists are taken as
-- the truth. A listed id that does not exist, is a group, or was listed
-- before (by this group or another) is dropped, and every aura's `parent`
-- is set from the lists.
local function ValidateGroups(displays)
	local owner = {}
	local id, data
	for id, data in pairs(displays) do
		if PA:IsGroup(data) then
			local kept = {}
			local i
			for i = 1, Compat.getn(data.controlledChildren) do
				local childId = data.controlledChildren[i]
				local child = displays[childId]
				if child and not PA:IsGroup(child) and not owner[childId] then
					owner[childId] = id
					table.insert(kept, childId)
				end
			end
			data.controlledChildren = kept
		end
	end
	for id, data in pairs(displays) do
		if not PA:IsGroup(data) then
			data.parent = owner[id]
		end
	end
end

function PA:ValidateAllData()
	local displays = self.db.global.displays
	local id, data
	for id, data in pairs(displays) do
		self:ValidateData(data)
	end
	ValidateGroups(displays)
end

local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	local k, v
	for k, v in pairs(value) do
		copy[k] = DeepCopy(v)
	end
	return copy
end
PA.DeepCopy = DeepCopy

function PA:GetData(id)
	return self.db.global.displays[id]
end

-- "New", then "New 2", "New 3", ... like WeakAuras' FindUnusedId.
function PA:FindUnusedId(base)
	local displays = self.db.global.displays
	if not displays[base] then return base end
	local n = 2
	while displays[base .. " " .. n] do
		n = n + 1
	end
	return base .. " " .. n
end

-- Takes `id` out of its group, if it is in one.
function PA:Ungroup(id)
	local data = self:GetData(id)
	if not (data and data.parent) then return end
	local group = self:GetData(data.parent)
	data.parent = nil
	if group then
		local index = IndexOf(group.controlledChildren, id)
		if index then table.remove(group.controlledChildren, index) end
	end
	self:RefreshRegion(id)
	-- A dynamic group closes the gap.
	if group then self:LayoutGroup(group.id) end
end

-- Puts `id` into `groupId` at `index` (the end when nil), out of any group
-- it was in before. Fails, returning false, for a group or a non-group
-- target.
function PA:AddToGroup(id, groupId, index)
	local data, group = self:GetData(id), self:GetData(groupId)
	if not (data and group) or self:IsGroup(data) or not self:IsGroup(group) then
		return false
	end
	self:Ungroup(id)
	local children = group.controlledChildren
	local count = Compat.getn(children)
	if not index or index > count + 1 then index = count + 1 end
	table.insert(children, index, id)
	data.parent = groupId
	self:RefreshRegion(id)
	return true
end

-- Moves `id` one place up (-1) or down (+1) in its group's order.
function PA:MoveInGroup(id, delta)
	local data = self:GetData(id)
	local group = data and data.parent and self:GetData(data.parent)
	if not group then return end
	local children = group.controlledChildren
	local index = IndexOf(children, id)
	local other = index and index + delta
	if not (other and other >= 1 and other <= Compat.getn(children)) then return end
	children[index], children[other] = children[other], children[index]
	self:LayoutGroup(group.id)
end

-- Whether `id` can move up (-1) or down (+1) in its group.
function PA:CanMoveInGroup(id, delta)
	local data = self:GetData(id)
	local group = data and data.parent and self:GetData(data.parent)
	if not group then return false end
	local index = IndexOf(group.controlledChildren, id)
	local other = index and index + delta
	return other ~= nil and other >= 1 and other <= Compat.getn(group.controlledChildren)
end

-- Creates an aura of `regionType` with that type's defaults and returns
-- its data. With `targetId` (WeakAuras' NewAura target) a new non-group
-- aura goes into that group, or next to that grouped aura in its group.
function PA:NewAura(regionType, targetId)
	local typeInfo = self.regionTypes[regionType]
	if not typeInfo then return end

	local data = DeepCopy(typeInfo.default)
	data.id = self:FindUnusedId(L["New"])
	data.regionType = regionType
	self:ValidateData(data)
	if not self:IsGroup(data) then AddDefaultSubTexts(data) end
	self.db.global.displays[data.id] = data

	local target = targetId and self:GetData(targetId)
	if target and not self:IsGroup(data) then
		if self:IsGroup(target) then
			self:AddToGroup(data.id, target.id)
		elseif target.parent then
			local group = self:GetData(target.parent)
			local index = group and IndexOf(group.controlledChildren, target.id)
			self:AddToGroup(data.id, target.parent, index and index + 1)
		end
	end
	return data
end

-- Moves an aura to a new id (WeakAuras.Rename), along with the group links
-- that name it. Fails, returning false, for an empty id or one another aura
-- already has.
function PA:RenameAura(oldId, newId)
	local displays = self.db.global.displays
	local data = displays[oldId]
	if not data or not newId or newId == "" then return false end
	if newId == oldId then return true end
	if displays[newId] then return false end

	displays[oldId] = nil
	data.id = newId
	displays[newId] = data

	local group = data.parent and displays[data.parent]
	if group then
		local index = IndexOf(group.controlledChildren, oldId)
		if index then group.controlledChildren[index] = newId end
	end
	if self:IsGroup(data) then
		local i
		for i = 1, Compat.getn(data.controlledChildren) do
			local child = displays[data.controlledChildren[i]]
			if child then child.parent = newId end
		end
	end

	self:RenameRegion(oldId, newId)
	return true
end

-- The id WeakAuras' DuplicateAura gives a copy of `id`: a trailing number
-- counted on ("New 2" -> "New 3"), otherwise " 2" appended; the first of
-- these that is free.
local function DuplicateId(id)
	local displays = PA.db.global.displays
	local base, n = id .. " ", 2
	local _, _, name, digits = string.find(id, "^(.-)(%d*)$")
	if name ~= "" and tonumber(digits) then
		base, n = name, tonumber(digits) + 1
	end
	while displays[base .. n] do
		n = n + 1
	end
	return base .. n
end

-- Stores a copy of `data` under a new id and uid, outside any group, a
-- group without its children.
local function StoreCopy(data)
	local copy = DeepCopy(data)
	copy.id = DuplicateId(data.id)
	copy.uid = PA:GenerateUniqueID()
	copy.parent = nil
	if PA:IsGroup(copy) then copy.controlledChildren = {} end
	PA.db.global.displays[copy.id] = copy
	return copy
end

-- Copies an aura (WeakAuras' "Duplicate") and returns the copy's id. A
-- grouped aura's copy goes right after it in its group; a group is copied
-- with a copy of each of its children, in order.
function PA:DuplicateAura(id)
	local data = self:GetData(id)
	if not data then return end
	local copy = StoreCopy(data)
	if self:IsGroup(data) then
		local i
		for i = 1, Compat.getn(data.controlledChildren) do
			local child = self:GetData(data.controlledChildren[i])
			if child then
				local childCopy = StoreCopy(child)
				childCopy.parent = copy.id
				table.insert(copy.controlledChildren, childCopy.id)
			end
		end
	elseif data.parent then
		local group = self:GetData(data.parent)
		local index = group and IndexOf(group.controlledChildren, id)
		if index then
			table.insert(group.controlledChildren, index + 1, copy.id)
			copy.parent = group.id
		end
	end
	self:RefreshRegion(copy.id)
	self:ScheduleTriggerUpdate()
	return copy.id
end

-- The number of auras DeleteAura(id, withChildren) removes.
function PA:CountDeleted(id, withChildren)
	local data = self:GetData(id)
	if not data then return 0 end
	if withChildren and self:IsGroup(data) then
		return 1 + Compat.getn(data.controlledChildren)
	end
	return 1
end

-- Deletes an aura. A group's children leave the group and stay (WeakAuras'
-- "Delete"), or with `withChildren` are deleted too ("Delete children and
-- group").
function PA:DeleteAura(id, withChildren)
	local data = self:GetData(id)
	if not data then return end

	local freed = {}
	if self:IsGroup(data) then
		local children = data.controlledChildren
		local i
		for i = 1, Compat.getn(children) do
			local child = self:GetData(children[i])
			if child then
				child.parent = nil
				if withChildren then
					self.db.global.displays[children[i]] = nil
					self:ReleaseRegion(children[i])
				else
					table.insert(freed, children[i])
				end
			end
		end
		data.controlledChildren = {}
	else
		self:Ungroup(id)
	end

	self.db.global.displays[id] = nil
	self:ReleaseRegion(id)
	-- Placed against the screen again, now that their group is gone.
	local i
	for i = 1, Compat.getn(freed) do
		self:RefreshRegion(freed[i])
	end
end

-- The texture an aura shows (WeakAuras' iconSource): its manual icon for
-- "Manual Icon" (0), trigger n's icon for n > 0, and for "Automatic" (-1)
-- the first active trigger's (Core/Triggers.lua); the question mark when
-- there is none. A group shows its groupIcon, or the default group icon.
-- The list shows a texture aura by its texture, a text and a model aura by
-- their type's icon, as WeakAuras' thumbnails show the region itself.
function PA:GetAuraIcon(data)
	if data.regionType == "texture" then
		return data.texture or self.DEFAULT_AURA_TEXTURE
	elseif data.regionType == "progresstexture" then
		return data.foregroundTexture or self.DEFAULT_AURA_TEXTURE
	elseif data.regionType == "text" then
		return self.TEXT_ICON
	elseif data.regionType == "model" then
		return self.MODEL_ICON
	end
	if self:IsGroup(data) then
		if data.groupIcon and data.groupIcon ~= "" then
			return data.groupIcon
		end
		if data.regionType == "dynamicgroup" then
			return self.DEFAULT_DYNAMIC_GROUP_ICON
		end
		return self.DEFAULT_GROUP_ICON
	end
	local source = data.iconSource or -1
	if source == 0 then
		if data.displayIcon and data.displayIcon ~= "" then
			return data.displayIcon
		end
		return self.DEFAULT_ICON
	end
	return self:StateIcon(self.auraStates[data.id], source) or self.DEFAULT_ICON
end

-- Sorted list of every aura id, for the options list.
function PA:GetSortedIds()
	local ids = {}
	local id
	for id in pairs(self.db.global.displays) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end
