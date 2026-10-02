-- The Actions tab (WeakAurasOptions ActionOptions.lua, GPLv2): "On Show"
-- and "On Hide", each a chat message (Core/Actions.lua) -- its type, its
-- text with the text placeholders, a whisper's target and a colour for the
-- chat frame and the error frame -- and a sound (Core/Sounds.lua): a
-- LibSharedMedia sound or a typed file path; "On Show" can repeat it. WeakAuras' sound channel, "Sound by
-- Kit ID", "Stop Sound", glow and custom code actions are not part of this
-- addon.

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

-- The sound file rows of the sound `options` describe (an action's, or a
-- condition's "sound" change value) into `args`, keyed `prefix` .. field,
-- ordered from `order` on: the sound, and the file path for "Custom". A
-- sound picked or a path typed plays at once, as in WeakAuras; the list's
-- rows have a play button of their own (LibConfig's LSM30_Sound). `hidden`
-- hides both (a condition's "Stop"), `disabled` greys them out.
function PA:AddSoundFileArgs(args, options, prefix, order, onChange, disabled, hidden)
	args[prefix .. "sound"] = {
		type = "select",
		name = L["Sound"],
		order = order,
		dialogControl = "LSM30_Sound",
		values = function() return PA:GetSoundValues() end,
		disabled = disabled,
		hidden = hidden,
		get = function() return options.sound end,
		set = function(info, value)
			options.sound = value
			if onChange then onChange() end
			PA:PlaySoundPath(value)
		end,
	}
	args[prefix .. "sound_path"] = {
		type = "input",
		name = L["Sound File Path"],
		desc = L["A file of the client (Sound\\Interface\\LevelUp.wav) or of an addon (Interface\\AddOns\\<addon>\\<file>.ogg). Unreal Azeroth plays .ogg and .wav files, not .mp3."],
		width = "full",
		order = order + 0.1,
		disabled = disabled,
		hidden = function()
			if hidden and hidden() then return true end
			return options.sound ~= PA.CUSTOM_SOUND
		end,
		get = function() return options.sound_path or "" end,
		set = function(info, value)
			options.sound_path = value
			if onChange then onChange() end
			PA:PlaySoundPath(value)
		end,
	}
end

-- The repeat interval row of a looping sound.
function PA:SoundRepeatArg(options, name, order, onChange, disabled, hidden)
	return {
		type = "range",
		name = name,
		desc = L["Seconds between two plays of the sound, while the aura is shown."],
		order = order,
		min = 0,
		softMax = 100,
		step = 0.1,
		bigStep = 1,
		disabled = disabled,
		hidden = hidden,
		get = function() return tonumber(options.sound_repeat) or 0 end,
		set = function(info, value)
			options.sound_repeat = value
			if onChange then onChange() end
		end,
	}
end

-- One of "On Show" (`when` "start") / "On Hide" ("finish").
local function WhenGroup(data, when, name, order, onChange)
	local actions = data.actions[when]
	local function Off() return not actions.do_message end
	local function SoundOff() return not actions.do_sound end
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

	args.do_sound = {
		type = "toggle",
		name = L["Play Sound"],
		order = 3,
		get = function() return actions.do_sound and true or false end,
		set = function(info, value)
			actions.do_sound = value
			if onChange then onChange() end
		end,
	}
	if when == "start" then
		args.do_loop = {
			type = "toggle",
			name = L["Loop"],
			order = 3.1,
			disabled = SoundOff,
			get = function() return actions.do_loop and true or false end,
			set = function(info, value)
				actions.do_loop = value
				if onChange then onChange() end
			end,
		}
		args.sound_repeat = PA:SoundRepeatArg(actions, L["Repeat After"], 3.2, onChange, SoundOff,
			function() return not actions.do_loop end)
	end
	PA:AddSoundFileArgs(args, actions, "", 3.3, onChange, SoundOff)
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
