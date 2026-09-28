-- The model region (WeakAuras RegionTypes/Model.lua, GPLv2): a 3D model from
-- the game files, the way WeakAuras draws it without SetTransform: the
-- model file, SetPosition(z, x, y), SetFacing and the animation sequence.
--
-- The region is the PlayerModel frame itself, not a frame holding one:
-- hiding a frame does not hide its child frames on Unreal Azeroth. The
-- model and its placement are applied again whenever the region is shown,
-- so nothing depends on the frame keeping them while hidden. Both clients
-- draw a model created this way (a spell effect,
-- "Spells\Holy_Missile_Low.mdx"); their model files are the .mdx paths of
-- the 1.12.1 client, so a path of a later client's form (".m2") is taken
-- with ".mdx" instead. The unit
-- models, SetTransform and the portrait zoom of WeakAuras are not part of
-- this region.
--
-- Animation: "Animate" plays the chosen sequence (an AnimationData id),
-- otherwise sequence 0 (Stand), as WeakAuras' SetAnimation. The 1.12.1
-- Model widget names this SetSequence; a model without an OnUpdateModel
-- script advances its animation on its own every frame.

local PA = unpack(PunyAuras)

-- `path` in the form the 1.12.1 client names its models: trimmed, with a
-- later client's ".m2" ending replaced by ".mdx".
function PA:ModelPath(path)
	path = string.gsub(path or "", "^%s+", "")
	path = string.gsub(path, "%s+$", "")
	path = string.gsub(path, "%.[mM]2$", ".mdx")
	return path
end

-- Sets the region's model and its placement from the data it was given.
local function ApplyModel(region)
	local data = region.modelData
	if not data then return end
	local path = PA:ModelPath(data.model_path)
	if path ~= "" then pcall(region.SetModel, region, path) end
	pcall(region.SetPosition, region, tonumber(data.model_z) or 0,
		tonumber(data.model_x) or 0, tonumber(data.model_y) or 0)
	pcall(region.SetFacing, region, math.rad(tonumber(data.rotation) or 0))
	local sequence = data.advance and (tonumber(data.sequence) or 0) or 0
	pcall(region.SetSequence, region, sequence)
end

local function Create(parent)
	local region = CreateFrame("PlayerModel", nil, parent)
	region:SetScript("OnShow", function() ApplyModel(region) end)
	region:Hide()
	return region
end

-- A grouped model is placed against its group, its size and offsets scaled
-- by the group's scale (PA:GetRegionAnchor).
local function Modify(region, data)
	local anchor, scale = PA:GetRegionAnchor(data)
	region:SetWidth(data.width * scale)
	region:SetHeight(data.height * scale)
	region:ClearAllPoints()
	region:SetPoint(data.selfPoint or "CENTER", anchor, data.anchorPoint or "CENTER",
		(data.xOffset or 0) * scale, (data.yOffset or 0) * scale)
	region.modelData = data
	ApplyModel(region)
end

PA.regionTypes.model.create = Create
PA.regionTypes.model.modify = Modify
