-- The Conditions tab (WeakAurasOptions ConditionOptions.lua, GPLv2): one
-- section per condition -- "Else If" (from the second condition on), its
-- check ("If" a trigger's or a global variable, an operator and a value,
-- or a combination: "All of" / "Any of" several checks), and its changes (a
-- region property and the value it takes) -- with "Add Property Change",
-- "Move Up", "Move Down" and "Delete", and "Add Condition" at the end.
-- Evaluation: Core/Conditions.lua.
--
-- A combination's checks follow it as their own "If" lines, as in
-- WeakAuras: each has a "(Remove)" entry, and one more, empty line after
-- them adds a check. Combinations nest up to MAX_DEPTH levels, WeakAuras'
-- limit. The first condition is never "Else If" (WeakAuras'
-- fixUpLinkedInFirstCondition). A "Chat Message" change takes the chat
-- message's rows of the Actions tab (PA:AddChatMessageArgs); the other
-- actions (sound, glow, custom code) are not part of this addon.

local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

local MAX_DEPTH = 3

-- WeakAuras' Private.operator_types, equality_operator_types and
-- string_operator_types.
local NUMBER_OPERATORS = {
	["=="] = "=", ["~="] = "!=", [">"] = ">", ["<"] = "<", [">="] = ">=", ["<="] = "<=",
}
local EQUALITY_OPERATORS = { ["=="] = "=", ["~="] = "!=" }
local STRING_OPERATORS = {
	["=="] = L["Is Exactly"],
	["find('%s')"] = L["Contains"],
	["match('%s')"] = L["Matches (Pattern)"],
}
local BOOL_VALUES = { [1] = L["True"], [0] = L["False"] }

-- The dropdown entry that removes a combination's check; the brackets sort
-- it first.
local REMOVE = "REMOVE"

local function Grouped(group, name)
	return group .. " / " .. name
end

local function IsCombination(check)
	return type(check) == "table" and (check.variable == "AND" or check.variable == "OR")
end

-- Every entry of an "If" line, keyed "<trigger>:<variable>" (-1 for the
-- global conditions, -2 for the combinations, offered above `depth`
-- MAX_DEPTH), and the remove entry on a combination's check.
local function CheckValues(data, depth)
	local values = {}
	local i
	for i = 1, Compat.getn(data.triggers) do
		local prefix = string.format(L["Trigger %d"], i)
		local variable, def
		for variable, def in pairs(PA:GetTriggerConditionVariables(data.triggers[i].trigger)) do
			values[i .. ":" .. variable] = Grouped(prefix, def.display)
		end
	end
	local variable, def
	for variable, def in pairs(PA.globalConditions) do
		values["-1:" .. variable] = Grouped(L["Global Conditions"], def.display)
	end
	if depth < MAX_DEPTH then
		values["-2:AND"] = Grouped(L["Combinations"], L["All of"])
		values["-2:OR"] = Grouped(L["Combinations"], L["Any of"])
	end
	if depth > 0 then
		values[REMOVE] = "(" .. L["Remove"] .. ")"
	end
	return values
end

-- The definition of the variable `check` tests, if it exists.
local function CheckDef(data, check)
	if check.trigger == -1 then return PA.globalConditions[check.variable or ""] end
	local trigger = data.triggers[check.trigger or 0]
	if not (trigger and check.variable) then return nil end
	return PA:GetTriggerConditionVariables(trigger.trigger)[check.variable]
end

-- An operator and a value that suit the variable's type.
local function ResetCheck(check, def)
	check.op, check.value = nil, nil
	if not def then return end
	if def.type == "bool" then
		check.value = 1
	elseif def.type == "number" or def.type == "timer" then
		check.op = "<"
	elseif def.type == "string" or def.type == "select" then
		check.op = "=="
	end
end

-- The check at `path` (indexes into nested `checks` lists) under `root`;
-- with `create`, missing ones are made on the way.
local function SubCheck(root, path, create)
	local check = root
	local i
	for i = 1, Compat.getn(path) do
		if type(check.checks) ~= "table" then
			if not create then return nil end
			check.checks = {}
		end
		local sub = check.checks[path[i]]
		if type(sub) ~= "table" then
			if not create then return nil end
			sub = {}
			check.checks[path[i]] = sub
		end
		check = sub
	end
	return check
end

-- A copy of a value, tables (colours) included.
local function CopyValue(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	local k, v
	for k, v in pairs(value) do
		copy[k] = v
	end
	return copy
end

-- A running `order` for the rows of one condition, in the order they are
-- added.
local function NextOrder(ctx)
	ctx.order = ctx.order + 1
	return ctx.order
end

-- The operator and value rows of `check`, by its variable's type.
local function AddCheckValueArgs(ctx, key, check, def)
	local args, Changed = ctx.args, ctx.Changed
	if not def or def.type == "alwaystrue" then return end
	if def.type == "bool" then
		args["value" .. key] = {
			type = "select",
			name = L["Value"],
			order = NextOrder(ctx),
			values = BOOL_VALUES,
			get = function() return tonumber(check.value) or 0 end,
			set = function(info, value)
				check.value = value
				Changed()
			end,
		}
		return
	end

	local operators = NUMBER_OPERATORS
	if def.type == "string" then
		operators = STRING_OPERATORS
	elseif def.type == "select" then
		operators = EQUALITY_OPERATORS
	end
	args["op" .. key] = {
		type = "select",
		name = L["Operator"],
		order = NextOrder(ctx),
		values = operators,
		get = function() return check.op end,
		set = function(info, value)
			check.op = value
			Changed()
		end,
	}

	if def.type == "select" then
		args["value" .. key] = {
			type = "select",
			name = L["Value"],
			order = NextOrder(ctx),
			values = def.values,
			get = function() return tonumber(check.value) or check.value end,
			set = function(info, value)
				check.value = value
				Changed()
			end,
		}
		return
	end
	args["value" .. key] = {
		type = "input",
		name = L["Value"],
		desc = def.type == "timer" and L["Seconds of the time left."] or nil,
		order = NextOrder(ctx),
		get = function() return check.value ~= nil and tostring(check.value) or "" end,
		set = function(info, value)
			if def.type == "string" then
				check.value = value
			else
				check.value = tonumber(value)
			end
			Changed()
		end,
	}
end

-- The name of the "If" line at `path`: "If" / "Else If" for the condition's
-- own check; for a combination's checks, one dash per level, and "and" /
-- "or" from the second one on.
local function IfLineName(ctx, path, parentVariable)
	local depth = Compat.getn(path)
	if depth == 0 then
		if ctx.condition.linked and ctx.index > 1 then return L["Else If"] end
		return L["If"]
	end
	local dashes = string.rep("-", depth)
	if path[depth] == 1 then return dashes end
	if parentVariable == "AND" then return dashes .. " " .. L["and"] end
	return dashes .. " " .. L["or"]
end

-- The "If" line of the check at `path`, and after it its operator and
-- value, or for a combination the lines of its checks and one more, empty
-- line that adds a check.
local function AddIfLine(ctx, path, parentVariable)
	local data, condition = ctx.data, ctx.condition
	local depth = Compat.getn(path)
	-- "if" / "op" / "value" for the condition's own check, "if_1_2" ... for
	-- a combination's, apart from the changes' "value<n>".
	local key = ""
	if depth > 0 then key = "_" .. table.concat(path, "_") end
	local check = SubCheck(condition.check, path, false)

	ctx.args["if" .. key] = {
		type = "select",
		name = IfLineName(ctx, path, parentVariable),
		order = NextOrder(ctx),
		width = "full",
		values = function() return CheckValues(data, depth) end,
		get = function()
			if check and check.trigger and check.variable then
				return check.trigger .. ":" .. check.variable
			end
		end,
		set = function(info, value)
			if value == REMOVE then
				local parentPath = {}
				local i
				for i = 1, depth - 1 do
					parentPath[i] = path[i]
				end
				local parent = SubCheck(condition.check, parentPath, false)
				if parent and type(parent.checks) == "table" then
					table.remove(parent.checks, path[depth])
				end
			else
				local _, _, trigger, variable = string.find(value, "^(%-?%d+):(.+)$")
				local target = SubCheck(condition.check, path, true)
				local wasCombination = IsCombination(target)
				target.trigger, target.variable = tonumber(trigger), variable
				if IsCombination(target) then
					target.op, target.value = nil, nil
					if not wasCombination then target.checks = {} end
				else
					target.checks = nil
					ResetCheck(target, CheckDef(data, target))
				end
			end
			ctx.Changed()
			ctx.Rebuild()
		end,
	}

	if IsCombination(check) then
		local count = type(check.checks) == "table" and Compat.getn(check.checks) or 0
		local i
		for i = 1, count + 1 do
			local subPath = {}
			local p
			for p = 1, depth do
				subPath[p] = path[p]
			end
			subPath[depth + 1] = i
			AddIfLine(ctx, subPath, check.variable)
		end
	elseif check then
		AddCheckValueArgs(ctx, key, check, CheckDef(data, check))
	end
end

-- The value row of change `change`, by its property's type.
local function ChangeValueArg(change, def, order, Changed)
	local function Get() return change.value end
	local function Set(info, value)
		change.value = value
		Changed()
	end
	if not def then
		return {
			type = "description",
			name = L["This property is not supported."],
			order = order,
		}
	end
	if def.type == "bool" then
		return { type = "toggle", name = L["Value"], order = order,
			get = function() return change.value and true or false end, set = Set }
	elseif def.type == "number" then
		return { type = "range", name = L["Value"], order = order, min = def.min, max = def.max,
			softMin = def.softMin, softMax = def.softMax, step = def.step, isPercent = def.isPercent,
			get = function() return tonumber(change.value) or def.min or 0 end, set = Set }
	elseif def.type == "color" then
		return {
			type = "color",
			name = L["Value"],
			hasAlpha = true,
			order = order,
			get = function()
				local c = type(change.value) == "table" and change.value or { 1, 1, 1, 1 }
				return c[1], c[2], c[3], c[4]
			end,
			set = function(info, r, g, b, a)
				change.value = { r, g, b, a }
				Changed()
			end,
		}
	elseif def.type == "list" then
		return { type = "select", name = L["Value"], order = order, values = def.values,
			get = Get, set = Set }
	end
	return { type = "input", name = L["Value"], order = order, width = "full",
		get = function() return change.value ~= nil and tostring(change.value) or "" end, set = Set }
end

-- The rows of the changes of the condition.
local function AddChangeArgs(ctx)
	local args, data, Changed, Rebuild = ctx.args, ctx.data, ctx.Changed, ctx.Rebuild
	local properties = PA:GetConditionProperties(data)
	local values = {}
	local key, def
	for key, def in pairs(properties) do
		values[key] = def.display
	end

	local changes = ctx.condition.changes
	local c
	for c = 1, Compat.getn(changes) do
		local change = changes[c]
		local index = c
		args["property" .. c] = {
			type = "select",
			name = string.format(L["Change %d"], c),
			order = NextOrder(ctx),
			values = values,
			get = function() return change.property end,
			set = function(info, value)
				if value == change.property then return end
				change.property = value
				if properties[value] and properties[value].type == "chat" then
					change.value = { message_type = "PRINT", message = "" }
				else
					change.value = CopyValue(PA:GetBaseProperty(data, value))
				end
				Changed()
				Rebuild()
			end,
		}
		local def = change.property and properties[change.property]
		if def and def.type == "chat" then
			if type(change.value) ~= "table" then change.value = {} end
			PA:AddChatMessageArgs(args, change.value, "chat" .. c .. "_", NextOrder(ctx), Changed)
			ctx.order = ctx.order + 1
		elseif change.property then
			args["value" .. c] = ChangeValueArg(change, def, NextOrder(ctx), Changed)
		end
		args["remove" .. c] = {
			type = "execute",
			name = L["Remove"],
			desc = L["Remove this property"],
			order = NextOrder(ctx),
			func = function()
				table.remove(changes, index)
				Changed()
				Rebuild()
			end,
		}
	end
	args.addChange = {
		type = "execute",
		name = L["Add Property Change"],
		order = 900,
		func = function()
			table.insert(changes, {})
			Changed()
			Rebuild()
		end,
	}
end

-- The first condition is never linked.
local function FixFirstLinked(conditions)
	if conditions[1] and conditions[1].linked then conditions[1].linked = false end
end

-- The section of condition `index`.
local function ConditionGroup(data, index, Changed, Rebuild)
	local conditions = data.conditions
	local condition = conditions[index]
	local count = Compat.getn(conditions)
	local ctx = {
		data = data, condition = condition, index = index, args = {}, order = 0,
		Changed = Changed, Rebuild = Rebuild,
	}
	local args = ctx.args

	if index > 1 then
		args.linked = {
			type = "toggle",
			name = L["Else If"],
			desc = L["Only while no earlier condition of the chain holds."],
			order = NextOrder(ctx),
			get = function() return condition.linked and true or false end,
			set = function(info, value)
				condition.linked = value and true or false
				Changed()
				Rebuild()
			end,
		}
	end
	AddIfLine(ctx, {}, nil)
	AddChangeArgs(ctx)

	args.moveUp = {
		type = "execute",
		name = L["Move Up"],
		order = 910,
		hidden = index <= 1,
		func = function()
			conditions[index], conditions[index - 1] = conditions[index - 1], conditions[index]
			FixFirstLinked(conditions)
			Changed()
			Rebuild()
		end,
	}
	args.moveDown = {
		type = "execute",
		name = L["Move Down"],
		order = 911,
		hidden = index >= count,
		func = function()
			conditions[index], conditions[index + 1] = conditions[index + 1], conditions[index]
			FixFirstLinked(conditions)
			Changed()
			Rebuild()
		end,
	}
	args.deleteCondition = {
		type = "execute",
		name = L["Delete"],
		order = 920,
		func = function()
			table.remove(conditions, index)
			FixFirstLinked(conditions)
			Changed()
			Rebuild()
		end,
	}

	return {
		type = "group",
		name = string.format(L["Condition %d"], index),
		inline = true,
		order = 10 + index,
		args = args,
	}
end

-- The Conditions tab of `data`. `onChange` runs after every value written;
-- `onRebuild` after a change to the tab's own rows (a condition, a check or
-- a change added, removed or moved, a check or a property picked).
function PA:GetConditionOptions(data, onChange, onRebuild)
	local function Changed()
		if onChange then onChange() end
	end
	local function Rebuild()
		if onRebuild then onRebuild() end
	end

	local args = {
		addCondition = {
			type = "execute",
			name = L["Add Condition"],
			order = 1000,
			func = function()
				table.insert(data.conditions, { check = {}, changes = {} })
				Changed()
				Rebuild()
			end,
		},
	}
	local i
	for i = 1, Compat.getn(data.conditions) do
		args["condition" .. i] = ConditionGroup(data, i, Changed, Rebuild)
	end

	return {
		type = "group",
		name = L["Conditions"],
		order = 3,
		args = args,
	}
end
