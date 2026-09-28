-- The Actions tab (WeakAurasOptions ActionOptions.lua, GPLv2): "On Show"
-- and "On Hide", each a chat message (Core/Actions.lua) -- its type, its
-- text with the text placeholders, a whisper's target and a colour for the
-- chat frame and the error frame. WeakAuras' sound, glow and custom code
-- actions are not part of this addon.

local PA, L = unpack(PunyAuras)

local PLACEHOLDER_HELP = "%p: time left or value, %t: duration or total, %n: name, %s: stacks, %%: a percent sign. %2.p reads trigger 2. \\n or a new line breaks the line."

-- The rows of a chat message's fields in `options` (an action's, or a
-- condition's "chat" change value) into `args`, keyed `prefix` .. field,
-- ordered from `order` on. `disabled` greys them out (an action whose
-- "Chat Message" is off).
function PA:AddChatMessageArgs(args, options, prefix, order, onChange, disabled)
	local function Changed()
		if onChange then onChange() end
	end
	local function Field(key)
		return {
			get = function() return options[key] end,
			set = function(info, value)
				options[key] = value
				Changed()
			end,
		}
	end

	local messageType = Field("message_type")
	args[prefix .. "message_type"] = {
		type = "select",
		name = L["Message Type"],
		order = order,
		values = PA.chatMessageTypes,
		disabled = disabled,
		get = messageType.get,
		set = messageType.set,
	}
	local dest = Field("message_dest")
	args[prefix .. "message_dest"] = {
		type = "input",
		name = L["Send To"],
		order = order + 0.1,
		disabled = disabled,
		hidden = function() return options.message_type ~= "WHISPER" end,
		get = function() return options.message_dest or "" end,
		set = dest.set,
	}
	args[prefix .. "message_color"] = {
		type = "color",
		name = L["Color"],
		order = order + 0.2,
		disabled = disabled,
		hidden = function() return not PA.coloredMessageTypes[options.message_type or ""] end,
		get = function()
			return tonumber(options.r) or 1, tonumber(options.g) or 1, tonumber(options.b) or 1
		end,
		set = function(info, r, g, b)
			options.r, options.g, options.b = r, g, b
			Changed()
		end,
	}
	local message = Field("message")
	args[prefix .. "message"] = {
		type = "input",
		name = L["Message"],
		desc = L[PLACEHOLDER_HELP],
		width = "full",
		order = order + 0.3,
		disabled = disabled,
		get = function() return options.message or "" end,
		set = message.set,
	}
end

-- One of "On Show" (`when` "start") / "On Hide" ("finish").
local function WhenGroup(data, when, name, order, onChange)
	local actions = data.actions[when]
	local function Off() return not actions.do_message end
	local args = {
		do_message = {
			type = "toggle",
			name = L["Chat Message"],
			order = 1,
			get = function() return actions.do_message and true or false end,
			set = function(info, value)
				actions.do_message = value
				if value and not actions.message_type then actions.message_type = "PRINT" end
				if onChange then onChange() end
			end,
		},
	}
	PA:AddChatMessageArgs(args, actions, "", 2, onChange, Off)
	return {
		type = "group",
		name = name,
		inline = true,
		order = order,
		args = args,
	}
end

-- The Actions tab of `data`; `onChange` runs after every value written.
function PA:GetActionOptions(data, onChange)
	return {
		type = "group",
		name = L["Actions"],
		order = 4,
		args = {
			start = WhenGroup(data, "start", L["On Show"], 1, onChange),
			finish = WhenGroup(data, "finish", L["On Hide"], 2, onChange),
		},
	}
end
