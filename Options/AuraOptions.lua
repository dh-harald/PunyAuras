-- Option tables of an aura: one group per tab of the options window, in the
-- AceConfig format WeakAuras builds them in (WeakAurasOptions DisplayOptions,
-- RegionOptions/Icon.lua, AuraBar.lua, CommonOptions.lua; GPLv2), rendered
-- into the right pane by LibConfig-1.0's embedded view.

local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

-- Tabs of the right pane, in WeakAuras' order, as far as they exist here.
-- A group has only its "Group" tab: WeakAuras' other tabs of a group edit
-- all of its children at once, which is not part of this addon.
PA.auraTabs = {
	{ key = "region", text = L["Display"] },
	{ key = "trigger", text = L["Trigger"] },
	{ key = "conditions", text = L["Conditions"] },
	{ key = "actions", text = L["Actions"] },
	{ key = "load", text = L["Load"] },
}
PA.groupTabs = {
	{ key = "group", text = L["Group"] },
}

-- The tabs of `data`.
function PA:GetAuraTabs(data)
	if self:IsGroup(data) then return self.groupTabs end
	return self.auraTabs
end

-- A bare icon name ("Spell_Holy_SealOfSalvation") is taken as an icon from
-- Interface\Icons; a path is used as given, in the form both clients draw
-- (PA:PortableIconPath).
local function NormalizeIconPath(value)
	value = value or ""
	if value == "" or string.find(value, "[\\/]") then
		return PA:PortableIconPath(value)
	end
	return "Interface\\Icons\\" .. value
end

-- WeakAuras' Private.grow_types, align_types and rotated_align_types, as far
-- as they exist here; the rotated names are for rows that grow sideways.
local GROW_TYPES = {
	LEFT = L["Left"],
	RIGHT = L["Right"],
	UP = L["Up"],
	DOWN = L["Down"],
	HORIZONTAL = L["Centered Horizontal"],
	VERTICAL = L["Centered Vertical"],
}
local ALIGN_TYPES = { LEFT = L["Left"], CENTER = L["Center"], RIGHT = L["Right"] }
local ROTATED_ALIGN_TYPES = { LEFT = L["Top"], CENTER = L["Center"], RIGHT = L["Bottom"] }
-- WeakAuras' Private.group_sort_types without "hybrid" and "custom".
local SORT_TYPES = {
	none = L["None"],
	ascending = L["Ascending"],
	descending = L["Descending"],
}

local function IsSideways(data)
	return data.grow == "LEFT" or data.grow == "RIGHT" or data.grow == "HORIZONTAL"
end

-- A dynamic group's layout settings (WeakAuras RegionOptions/DynamicGroup.lua),
-- added to the "Group" tab's `args`. Grow and align also set `selfPoint`,
-- as there. Limits and steps are WeakAuras', but for the space's slider.
local function AddDynamicGroupOptions(args, data, onChange)
	local function SetLayout(info, value)
		data[info[Compat.getn(info)]] = value
		data.selfPoint = PA:DynamicGroupSelfPoint(data)
		if onChange then onChange(data) end
	end

	args.grow = {
		type = "select",
		name = L["Grow"],
		order = 3,
		values = GROW_TYPES,
		set = SetLayout,
	}
	args.align = {
		type = "select",
		name = L["Align"],
		order = 4,
		values = ALIGN_TYPES,
		set = SetLayout,
		hidden = function() return IsSideways(data) end,
	}
	args.rotatedAlign = {
		type = "select",
		name = L["Align"],
		order = 4,
		values = ROTATED_ALIGN_TYPES,
		get = function() return data.align end,
		set = function(info, value)
			data.align = value
			data.selfPoint = PA:DynamicGroupSelfPoint(data)
			if onChange then onChange(data) end
		end,
		hidden = function() return not IsSideways(data) end,
	}
	-- The slider reaches below 0 (WeakAuras' starts at 0 and takes a
	-- negative space only typed): overlapping children, e.g. models whose
	-- frame is larger than what they draw.
	args.space = {
		type = "range",
		name = L["Space"],
		softMin = -100,
		softMax = 300,
		bigStep = 1,
		order = 5,
	}
	args.sort = {
		type = "select",
		name = L["Sort"],
		order = 6,
		values = SORT_TYPES,
	}
	args.useLimit = {
		type = "toggle",
		name = L["Limit"],
		order = 7,
	}
	args.limit = {
		type = "range",
		name = L["Limit"],
		min = 0,
		softMax = 20,
		step = 1,
		order = 8,
		disabled = function() return not data.useLimit end,
	}
end

-- The "Group" tab (WeakAuras RegionOptions/Group.lua, and DynamicGroup.lua
-- for a dynamic group): the group's icon in the list, a dynamic group's
-- layout, the scale and the position. The scale's limits and steps are
-- WeakAuras'.
local function GetGroupOptions(data, onChange)
	local function Get(info)
		return data[info[Compat.getn(info)]]
	end
	local function Set(info, value)
		data[info[Compat.getn(info)]] = value
		if onChange then onChange(data) end
	end

	local screenWidth = math.ceil(GetScreenWidth() / 20) * 20
	local screenHeight = math.ceil(GetScreenHeight() / 20) * 20
	local dynamic = (data.regionType == "dynamicgroup")

	local options = {
		type = "group",
		name = data.id,
		args = {
			group = {
				type = "group",
				name = L["Group"],
				order = 1,
				get = Get,
				set = Set,
				args = {
					groupHeader = {
						type = "header",
						name = dynamic and L["Dynamic Group Settings"] or L["Group Settings"],
						order = 0,
					},
					groupIcon = {
						type = "input",
						name = L["Group Icon"],
						desc = L["Set Thumbnail Icon"],
						order = 1,
						get = function()
							return data.groupIcon and tostring(data.groupIcon) or ""
						end,
						set = function(info, value)
							data.groupIcon = NormalizeIconPath(value)
							if onChange then onChange(data) end
						end,
					},
					chooseIcon = {
						type = "execute",
						name = L["Choose"],
						order = 2,
						func = function() PA:OpenIconPicker(data) end,
					},
					scale = {
						type = "range",
						name = L["Group Scale"],
						min = 0.05,
						max = 10,
						softMax = 2,
						step = 0.01,
						bigStep = 0.05,
						order = 11,
					},
					xOffset = {
						type = "range",
						name = L["X Offset"],
						min = -screenWidth,
						max = screenWidth,
						step = 1,
						order = 12,
					},
					yOffset = {
						type = "range",
						name = L["Y Offset"],
						min = -screenHeight,
						max = screenHeight,
						step = 1,
						order = 13,
					},
				},
			},
		},
	}
	if dynamic then
		AddDynamicGroupOptions(options.args.group.args, data, onChange)
	end
	return options
end

-- WeakAuras' Private.orientation_types; the names say which way the bar
-- empties.
local ORIENTATION_TYPES = {
	HORIZONTAL_INVERSE = L["Left to Right"],
	HORIZONTAL = L["Right to Left"],
	VERTICAL = L["Bottom to Top"],
	VERTICAL_INVERSE = L["Top to Bottom"],
}

-- WeakAuras' icon_side_types and rotated_icon_side_types.
local ICON_SIDE_TYPES = { LEFT = L["Left"], RIGHT = L["Right"] }
local ROTATED_ICON_SIDE_TYPES = { LEFT = L["Top"], RIGHT = L["Bottom"] }

-- Every LibSharedMedia statusbar texture by name, built on every render:
-- other addons register theirs at load time or later.
local function StatusbarValues()
	local values = {}
	local LSM = LibStub("LibSharedMedia-3.0", true)
	local names = LSM and LSM:List("statusbar")
	if names then
		local i
		for i = 1, Compat.getn(names) do
			values[names[i]] = names[i]
		end
	end
	return values
end

-- The manual icon options, shared by the icon and the bar: WeakAuras'
-- Private.IconSources (-1 takes the icon from the first active trigger, 0 is
-- the manual icon, n the icon of trigger n), the manual icon and its picker.
-- `order` and `step` place the three rows; `hidden` hides them all.
local function AddIconSourceArgs(args, data, onChange, order, step, hidden)
	local function ManualHidden()
		return (hidden and hidden()) or data.iconSource ~= 0
	end
	args.iconSource = {
		type = "select",
		name = L["Icon Source"],
		order = order,
		hidden = hidden,
		values = function()
			local values = {
				[-1] = L["Automatic"],
				[0] = L["Manual Icon"],
			}
			local i
			for i = 1, Compat.getn(data.triggers) do
				values[i] = string.format(L["Trigger %d"], i)
			end
			return values
		end,
	}
	args.displayIcon = {
		type = "input",
		name = L["Manual Icon"],
		desc = L["An icon name from Interface\\Icons (e.g. Spell_Holy_SealOfSalvation) or a full texture path."],
		order = order + step,
		hidden = ManualHidden,
		get = function()
			return data.displayIcon and tostring(data.displayIcon) or ""
		end,
		set = function(info, value)
			data.displayIcon = NormalizeIconPath(value)
			if onChange then onChange(data) end
		end,
	}
	args.chooseIcon = {
		type = "execute",
		name = L["Choose"],
		order = order + 2 * step,
		hidden = ManualHidden,
		func = function() PA:OpenIconPicker(data) end,
	}
end

-- A colour option on `data[key]`, stored as { r, g, b, a }.
local function ColorArg(data, key, name, order, onChange, hidden)
	return {
		type = "color",
		name = name,
		hasAlpha = true,
		order = order,
		hidden = hidden,
		get = function()
			local c = data[key] or { 1, 1, 1, 1 }
			return c[1], c[2], c[3], c[4]
		end,
		set = function(info, r, g, b, a)
			data[key] = { r, g, b, a }
			if onChange then onChange(data) end
		end,
	}
end

-- The icon region's settings (WeakAuras RegionOptions/Icon.lua).
local function IconDisplayArgs(data, onChange)
	local args = {
		iconHeader = {
			type = "header",
			name = L["Icon Settings"],
			order = 1,
		},
		color = ColorArg(data, "color", L["Color"], 2, onChange),
		desaturate = {
			type = "toggle",
			name = L["Desaturate"],
			order = 3,
		},
		alpha = {
			type = "range",
			name = L["Alpha"],
			min = 0,
			max = 1,
			step = 0.01,
			isPercent = true,
			order = 7,
		},
		zoom = {
			type = "range",
			name = L["Zoom"],
			min = 0,
			max = 1,
			step = 0.01,
			isPercent = true,
			order = 8,
		},
	}
	AddIconSourceArgs(args, data, onChange, 4, 1)
	return args
end

-- The bar region's settings (WeakAuras RegionOptions/AuraBar.lua), as far
-- as they exist here. Changing the orientation turns the bar as WeakAuras
-- does: between horizontal and vertical the width and the height swap, and
-- the icon keeps its end of the bar.
local function AuraBarDisplayArgs(data, onChange)
	local function NoIcon() return not data.icon end
	local function IsVertical()
		return string.find(data.orientation or "", "VERTICAL") ~= nil
	end

	local args = {
		barHeader = {
			type = "header",
			name = L["Bar Settings"],
			order = 1,
		},
		texture = {
			type = "select",
			dialogControl = "LSM30_Statusbar",
			name = L["Bar Texture"],
			order = 2,
			values = StatusbarValues,
		},
		orientation = {
			type = "select",
			name = L["Orientation"],
			order = 25,
			values = ORIENTATION_TYPES,
			set = function(info, value)
				local old = data.orientation or "HORIZONTAL"
				local function Has(text, part) return string.find(text, part) ~= nil end
				if Has(old, "INVERSE") ~= Has(value, "INVERSE") then
					data.icon_side = (data.icon_side == "LEFT") and "RIGHT" or "LEFT"
				end
				if Has(old, "HORIZONTAL") ~= Has(value, "HORIZONTAL") then
					data.width, data.height = data.height, data.width
					data.icon_side = (data.icon_side == "LEFT") and "RIGHT" or "LEFT"
				end
				data.orientation = value
				if onChange then onChange(data) end
			end,
		},
		inverse = {
			type = "toggle",
			name = L["Inverse"],
			order = 35,
		},
		barColorHeader = {
			type = "header",
			name = L["Bar Color Settings"],
			order = 39,
		},
		barColor = ColorArg(data, "barColor", L["Bar Color"], 39.3, onChange),
		backgroundColor = ColorArg(data, "backgroundColor", L["Background Color"], 39.5, onChange),
		alpha = {
			type = "range",
			name = L["Bar Alpha"],
			min = 0,
			max = 1,
			step = 0.01,
			isPercent = true,
			order = 39.6,
		},
		iconHeader = {
			type = "header",
			name = L["Icon Settings"],
			order = 40.1,
		},
		icon = {
			type = "toggle",
			name = L["Show Icon"],
			order = 40.2,
		},
		icon_side = {
			type = "select",
			name = L["Icon Position"],
			order = 40.3,
			values = function()
				if IsVertical() then return ROTATED_ICON_SIDE_TYPES end
				return ICON_SIDE_TYPES
			end,
			hidden = NoIcon,
		},
		desaturate = {
			type = "toggle",
			name = L["Desaturate"],
			order = 40.8,
			hidden = NoIcon,
		},
		icon_color = ColorArg(data, "icon_color", L["Color"], 40.9, onChange, NoIcon),
		zoom = {
			type = "range",
			name = L["Zoom"],
			min = 0,
			max = 1,
			step = 0.01,
			isPercent = true,
			order = 40.91,
			hidden = NoIcon,
		},
	}
	AddIconSourceArgs(args, data, onChange, 40.4, 0.1, NoIcon)
	return args
end

-- Every LibSharedMedia font by name, built on every render.
local function FontValues()
	local values = {}
	local LSM = LibStub("LibSharedMedia-3.0", true)
	local names = LSM and LSM:List("font")
	if names then
		local i
		for i = 1, Compat.getn(names) do
			values[names[i]] = names[i]
		end
	end
	return values
end

-- WeakAuras' Private.font_flags without its Slug flags (a later client's),
-- WeakAuras' justify_types and text_automatic_width.
local FONT_FLAGS = {
	None = L["None"],
	MONOCHROME = L["Monochrome"],
	OUTLINE = L["Outline"],
	THICKOUTLINE = L["Thick Outline"],
	["MONOCHROME|OUTLINE"] = L["Monochrome Outline"],
	["MONOCHROME|THICKOUTLINE"] = L["Monochrome Thick Outline"],
}
local JUSTIFY_TYPES = { LEFT = L["Left"], CENTER = L["Center"], RIGHT = L["Right"] }
local AUTOMATIC_WIDTH_TYPES = { Auto = L["Automatic"], Fixed = L["Fixed"] }

-- The text region's settings (WeakAuras RegionOptions/Text.lua), without the
-- custom text and the per-placeholder formats. Font, size and outline apply
-- on the 1.12.1 client only: Unreal Azeroth ignores SetFont.
local function TextDisplayArgs(data, onChange)
	local screenWidth = math.ceil(GetScreenWidth() / 20) * 20
	return {
		textHeader = {
			type = "header",
			name = L["Text Settings"],
			order = 1,
		},
		displayText = {
			type = "input",
			name = L["Display Text"],
			desc = L["%p: time left or value, %t: duration or total, %n: name, %s: stacks, %%: a percent sign. %2.p reads trigger 2. \\n or a new line breaks the line."],
			multiline = 4,
			width = "full",
			order = 10,
		},
		font = {
			type = "select",
			dialogControl = "LSM30_Font",
			name = L["Font"],
			order = 45,
			values = FontValues,
		},
		fontSize = {
			type = "range",
			name = L["Size"],
			min = 6,
			max = 72,
			step = 1,
			order = 46,
		},
		color = ColorArg(data, "color", L["Text Color"], 47, onChange),
		outline = {
			type = "select",
			name = L["Outline"],
			order = 47.5,
			values = FONT_FLAGS,
		},
		shadowColor = ColorArg(data, "shadowColor", L["Shadow Color"], 48.3, onChange),
		shadowXOffset = {
			type = "range",
			name = L["Shadow X Offset"],
			min = -15,
			max = 15,
			step = 1,
			order = 48.5,
		},
		shadowYOffset = {
			type = "range",
			name = L["Shadow Y Offset"],
			min = -15,
			max = 15,
			step = 1,
			order = 48.6,
		},
		justify = {
			type = "select",
			name = L["Justify"],
			order = 48.8,
			values = JUSTIFY_TYPES,
		},
		automaticWidth = {
			type = "select",
			name = L["Width"],
			order = 49,
			values = AUTOMATIC_WIDTH_TYPES,
		},
		fixedWidth = {
			type = "range",
			name = L["Width"],
			min = 1,
			max = screenWidth,
			step = 1,
			order = 49.1,
			hidden = function() return data.automaticWidth ~= "Fixed" end,
		},
	}
end

-- A texture path option on `data[key]` and its "Choose" button, which opens
-- the texture picker. A typed path is kept in the form both clients draw.
local function AddTextureArgs(args, data, onChange, key, name, order, hidden)
	args[key] = {
		type = "input",
		name = name,
		desc = L["A texture path, e.g. Interface\\Icons\\Spell_Nature_LightningShield; Choose offers the textures that come with the addon."],
		order = order,
		hidden = hidden,
		get = function()
			return data[key] and tostring(data[key]) or ""
		end,
		set = function(info, value)
			data[key] = PA:PortableIconPath(value or "")
			if onChange then onChange(data) end
		end,
	}
	args[key .. "Choose"] = {
		type = "execute",
		name = L["Choose"],
		order = order + 0.1,
		hidden = hidden,
		func = function() PA:OpenTexturePicker(data, key) end,
	}
end

-- The texture region's settings (WeakAuras RegionOptions/Texture.lua),
-- without the blend mode, the texture wrap and the rotation.
local function TextureDisplayArgs(data, onChange)
	local args = {
		textureHeader = {
			type = "header",
			name = L["Texture Settings"],
			order = 1,
		},
		color = ColorArg(data, "color", L["Color"], 3, onChange),
		desaturate = {
			type = "toggle",
			name = L["Desaturate"],
			order = 4,
		},
		alpha = {
			type = "range",
			name = L["Alpha"],
			min = 0,
			max = 1,
			step = 0.01,
			isPercent = true,
			order = 5,
		},
		mirror = {
			type = "toggle",
			name = L["Mirror"],
			order = 7,
		},
	}
	AddTextureArgs(args, data, onChange, "texture", L["Texture"], 1.5)
	return args
end

-- The progress texture region's settings (WeakAuras RegionOptions/
-- ProgressTexture.lua), its linear orientations, without the blend mode,
-- the texture wrap, the rotations, the crop and the slant.
local function ProgressTextureDisplayArgs(data, onChange)
	local args = {
		progressTextureHeader = {
			type = "header",
			name = L["Progress Texture Settings"],
			order = 0.5,
		},
		mirror = {
			type = "toggle",
			name = L["Mirror"],
			order = 10,
		},
		sameTexture = {
			type = "toggle",
			name = L["Same"],
			desc = L["The background uses the foreground texture."],
			order = 15,
		},
		desaturateForeground = {
			type = "toggle",
			name = L["Desaturate Foreground"],
			order = 17.5,
		},
		desaturateBackground = {
			type = "toggle",
			name = L["Desaturate Background"],
			order = 17.6,
		},
		backgroundOffset = {
			type = "range",
			name = L["Background Offset"],
			min = 0,
			max = 100,
			softMax = 25,
			step = 1,
			order = 25,
		},
		foregroundColor = ColorArg(data, "foregroundColor", L["Foreground Color"], 30, onChange),
		orientation = {
			type = "select",
			name = L["Orientation"],
			order = 35,
			values = ORIENTATION_TYPES,
		},
		backgroundColor = ColorArg(data, "backgroundColor", L["Background Color"], 37, onChange),
		compress = {
			type = "toggle",
			name = L["Compress"],
			order = 40,
		},
		inverse = {
			type = "toggle",
			name = L["Inverse"],
			order = 41,
		},
		alpha = {
			type = "range",
			name = L["Alpha"],
			min = 0,
			max = 1,
			step = 0.01,
			isPercent = true,
			order = 42,
		},
	}
	AddTextureArgs(args, data, onChange, "foregroundTexture", L["Foreground Texture"], 1)
	AddTextureArgs(args, data, onChange, "backgroundTexture", L["Background Texture"], 5,
		function() return data.sameTexture end)
	return args
end

-- The model region's settings (WeakAuras RegionOptions/Model.lua), the
-- SetPosition / SetFacing ones. The model's offsets move it inside its
-- frame, in the client's model units.
local function ModelDisplayArgs(data, onChange)
	local function Offset(name, order)
		return {
			type = "range",
			name = name,
			min = -20,
			max = 20,
			step = 0.01,
			bigStep = 0.05,
			order = order,
		}
	end
	return {
		modelHeader = {
			type = "header",
			name = L["Model Settings"],
			order = 1,
		},
		model_path = {
			type = "input",
			name = L["Model"],
			desc = L["A model file of the game, e.g. Spells\\Holy_Missile_Low.mdx. A path ending in .m2 (a later client's) is taken with .mdx."],
			width = "full",
			order = 2,
			set = function(info, value)
				data.model_path = PA:ModelPath(value)
				if onChange then onChange(data) end
			end,
		},
		chooseModel = {
			type = "execute",
			name = L["Choose"],
			order = 3,
			func = function() PA:OpenModelPicker(data) end,
		},
		model_z = Offset(L["Z Offset"], 20),
		model_x = Offset(L["X Offset"], 30),
		model_y = Offset(L["Y Offset"], 40),
		rotation = {
			type = "range",
			name = L["Rotation"],
			min = 0,
			max = 360,
			step = 1,
			bigStep = 3,
			order = 45,
		},
		advance = {
			type = "toggle",
			name = L["Animate"],
			order = 50,
		},
		-- An AnimationData id (0 is Stand). Auras made before this setting
		-- have no value; they show WeakAuras' default.
		sequence = {
			type = "range",
			name = L["Animation Sequence"],
			min = 0,
			softMax = 1499,
			step = 1,
			bigStep = 1,
			order = 51,
			get = function() return tonumber(data.sequence) or 1 end,
			disabled = function() return not data.advance end,
		},
	}
end

-- Size and position (WeakAuras' position options), from `order` on. A
-- dynamic group places its children itself, so their own offsets are not
-- offered (as in WeakAuras). `noSize` leaves out the size, for a region
-- sized by its content (the text).
local function AddPositionArgs(args, data, order, noSize)
	local screenWidth = math.ceil(GetScreenWidth() / 20) * 20
	local screenHeight = math.ceil(GetScreenHeight() / 20) * 20
	local function InDynamicGroup()
		local group = data.parent and PA:GetData(data.parent)
		return group ~= nil and group.regionType == "dynamicgroup"
	end

	args.positionHeader = {
		type = "header",
		name = L["Position and Size Settings"],
		order = order,
	}
	if not noSize then
		args.width = {
			type = "range",
			name = L["Width"],
			min = 1,
			max = screenWidth,
			step = 1,
			order = order + 1,
		}
		args.height = {
			type = "range",
			name = L["Height"],
			min = 1,
			max = screenHeight,
			step = 1,
			order = order + 2,
		}
	end
	args.xOffset = {
		type = "range",
		name = L["X Offset"],
		min = -screenWidth,
		max = screenWidth,
		step = 1,
		order = order + 3,
		hidden = InDynamicGroup,
	}
	args.yOffset = {
		type = "range",
		name = L["Y Offset"],
		min = -screenHeight,
		max = screenHeight,
		step = 1,
		order = order + 4,
		hidden = InDynamicGroup,
	}
end

-- WeakAuras' Private.point_types names, and the anchor points a sub-region
-- text is offered per region type (WeakAuras RegionOptions/Icon.lua and
-- AuraBar.lua `anchorPoints`, Private.default_types_for_anchor for the
-- others), as far as they exist here (Regions/SubTexts.lua): no "Fill Area"
-- anchors and no spark.
local POINT_NAMES = {
	BOTTOMLEFT = L["Bottom Left"],
	BOTTOM = L["Bottom"],
	BOTTOMRIGHT = L["Bottom Right"],
	RIGHT = L["Right"],
	TOPRIGHT = L["Top Right"],
	TOP = L["Top"],
	TOPLEFT = L["Top Left"],
	LEFT = L["Left"],
	CENTER = L["Center"],
}

-- Every point of POINT_NAMES under `prefix` into `values`, named "`group`
-- / point"; `skipCenter` leaves the centre out.
local function AddAnchorPoints(values, prefix, group, skipCenter)
	local point, name
	for point, name in pairs(POINT_NAMES) do
		if not (skipCenter and point == "CENTER") then
			values[prefix .. point] = group and (group .. " / " .. name) or name
		end
	end
end

local function SubTextAnchorValues(regionType)
	local values = {}
	if regionType == "icon" then
		values.CENTER = L["Center"]
		AddAnchorPoints(values, "", L["Edge"], true)
		AddAnchorPoints(values, "INNER_", L["Inner"], true)
		AddAnchorPoints(values, "OUTER_", L["Outer"], true)
	elseif regionType == "aurabar" then
		AddAnchorPoints(values, "", L["Background"])
		AddAnchorPoints(values, "INNER_", L["Background Inner"])
		AddAnchorPoints(values, "ICON_", L["Icon"])
	else
		AddAnchorPoints(values, "")
	end
	return values
end

local function SubTextSelfPointValues()
	local values = {}
	AddAnchorPoints(values, "")
	values.AUTO = L["Automatic"]
	return values
end

-- The section of sub-region text `index` of `data.subRegions`, the
-- `number`-th text (WeakAuras SubRegionOptions/SubText.lua), without the
-- rotation, the smooth font, the overflow and the per-placeholder formats.
-- The justify setting only applies to a text of fixed width: a text of
-- automatic width lines up on its anchor's side (Regions/SubTexts.lua).
local function SubTextGroup(data, index, number, onChange, onRebuild)
	local sub = data.subRegions[index]
	local function Changed()
		if onChange then onChange(data) end
	end
	local function NotFixed() return sub.text_automaticWidth ~= "Fixed" end
	local screenWidth = math.ceil(GetScreenWidth() / 20) * 20
	local screenHeight = math.ceil(GetScreenHeight() / 20) * 20

	return {
		type = "group",
		name = string.format(L["Text %d"], number),
		inline = true,
		order = 100 + index,
		get = function(info)
			return sub[info[Compat.getn(info)]]
		end,
		set = function(info, value)
			sub[info[Compat.getn(info)]] = value
			Changed()
		end,
		args = {
			text_visible = {
				type = "toggle",
				name = L["Show Text"],
				order = 1,
			},
			text_text = {
				type = "input",
				name = L["Display Text"],
				desc = L["%p: time left or value, %t: duration or total, %n: name, %s: stacks, %%: a percent sign. %2.p reads trigger 2. \\n or a new line breaks the line."],
				width = "full",
				order = 2,
			},
			text_font = {
				type = "select",
				dialogControl = "LSM30_Font",
				name = L["Font"],
				order = 3,
				values = FontValues,
			},
			text_fontSize = {
				type = "range",
				name = L["Size"],
				min = 6,
				max = 72,
				step = 1,
				order = 4,
			},
			text_color = ColorArg(sub, "text_color", L["Color"], 5, Changed),
			text_fontType = {
				type = "select",
				name = L["Outline"],
				order = 6,
				values = FONT_FLAGS,
			},
			text_shadowColor = ColorArg(sub, "text_shadowColor", L["Shadow Color"], 7, Changed),
			text_shadowXOffset = {
				type = "range",
				name = L["Shadow X Offset"],
				min = -15,
				max = 15,
				step = 1,
				order = 8,
			},
			text_shadowYOffset = {
				type = "range",
				name = L["Shadow Y Offset"],
				min = -15,
				max = 15,
				step = 1,
				order = 9,
			},
			text_automaticWidth = {
				type = "select",
				name = L["Width"],
				order = 10,
				values = AUTOMATIC_WIDTH_TYPES,
			},
			text_fixedWidth = {
				type = "range",
				name = L["Width"],
				min = 1,
				softMax = 200,
				max = screenWidth,
				step = 1,
				order = 11,
				hidden = NotFixed,
			},
			text_justify = {
				type = "select",
				name = L["Justify"],
				order = 12,
				values = JUSTIFY_TYPES,
				hidden = NotFixed,
			},
			text_selfPoint = {
				type = "select",
				name = L["Anchor"],
				order = 13,
				values = SubTextSelfPointValues,
			},
			anchor_point = {
				type = "select",
				name = L["To Frame's"],
				order = 14,
				values = function() return SubTextAnchorValues(data.regionType) end,
			},
			text_anchorXOffset = {
				type = "range",
				name = L["X Offset"],
				min = -screenWidth,
				max = screenWidth,
				softMin = -100,
				softMax = 100,
				step = 1,
				order = 15,
			},
			text_anchorYOffset = {
				type = "range",
				name = L["Y Offset"],
				min = -screenHeight,
				max = screenHeight,
				softMin = -100,
				softMax = 100,
				step = 1,
				order = 16,
			},
			deleteText = {
				type = "execute",
				name = L["Delete"],
				order = 20,
				func = function()
					PA:DeleteSubRegion(data, index)
					Changed()
					if onRebuild then onRebuild() end
				end,
			},
		},
	}
end

-- The sub-region texts of `data` and "Add Text", after the region's own
-- settings. Entries of other types in data.subRegions keep their places.
local function AddSubTextArgs(args, data, onChange, onRebuild)
	local number = 0
	local i
	for i = 1, Compat.getn(data.subRegions) do
		local sub = data.subRegions[i]
		if type(sub) == "table" and sub.type == "subtext" then
			number = number + 1
			args["subtext" .. i] = SubTextGroup(data, i, number, onChange, onRebuild)
		end
	end
	args.addText = {
		type = "execute",
		name = L["Add Text"],
		order = 1000,
		func = function()
			table.insert(data.subRegions, PA:DefaultSubText(data.regionType))
			if onChange then onChange(data) end
			if onRebuild then onRebuild() end
		end,
	}
end

-- The Display tab's settings of a region type.
local function DisplayArgs(data, onChange, onRebuild)
	local args
	if data.regionType == "aurabar" then
		args = AuraBarDisplayArgs(data, onChange)
		AddPositionArgs(args, data, 60)
	elseif data.regionType == "text" then
		args = TextDisplayArgs(data, onChange)
		AddPositionArgs(args, data, 60, true)
	elseif data.regionType == "texture" then
		args = TextureDisplayArgs(data, onChange)
		AddPositionArgs(args, data, 60)
	elseif data.regionType == "progresstexture" then
		args = ProgressTextureDisplayArgs(data, onChange)
		AddPositionArgs(args, data, 60)
	elseif data.regionType == "model" then
		args = ModelDisplayArgs(data, onChange)
		AddPositionArgs(args, data, 60)
	else
		args = IconDisplayArgs(data, onChange)
		AddPositionArgs(args, data, 10)
	end
	if PA.subTextRegionTypes[data.regionType] then
		AddSubTextArgs(args, data, onChange, onRebuild)
	end
	return args
end

-- The whole options table of `data`. `onChange` runs after every value that
-- was written, so the caller can update what shows the aura; `onRebuild`
-- after a change to the table's own structure (a trigger added or removed),
-- when the caller has to build and open it again.
function PA:GetAuraOptions(data, onChange, onRebuild)
	if self:IsGroup(data) then
		return GetGroupOptions(data, onChange)
	end

	-- The key of a leaf is the last element of its info path.
	local function Get(info)
		return data[info[Compat.getn(info)]]
	end
	local function Set(info, value)
		data[info[Compat.getn(info)]] = value
		if onChange then onChange(data) end
	end

	return {
		type = "group",
		name = data.id,
		args = {
			region = {
				type = "group",
				name = L["Display"],
				order = 1,
				get = Get,
				set = Set,
				args = DisplayArgs(data, onChange, onRebuild),
			},
			trigger = PA:GetTriggerOptions(data, function()
				if onChange then onChange(data) end
			end, onRebuild),
			conditions = PA:GetConditionOptions(data, function()
				if onChange then onChange(data) end
			end, onRebuild),
			actions = PA:GetActionOptions(data, function()
				if onChange then onChange(data) end
			end),
			load = PA:GetLoadOptions(data, function()
				if onChange then onChange(data) end
			end),
		},
	}
end
