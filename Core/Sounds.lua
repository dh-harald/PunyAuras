-- Sounds: the "Play Sound" actions and the conditions' "Sound" change
-- (WeakAuras RegionPrototype.lua SoundPlay / SoundRepeatStop, Types.lua
-- sound list; GPLv2).
--
-- WeakAuras' own sounds ship in Media/Sounds and are registered with
-- LibSharedMedia-3.0 under WeakAuras' names (SOUNDS; the files are built by
-- scripts/make-sounds.py, which checks its list against this one). A sound
-- option stores a path, as WeakAuras does: `sound` is a LibSharedMedia
-- sound's path, or CUSTOM with the path typed into `sound_path`.
--
-- Playing is PlaySoundFile(path, "Master") on both clients, with the path
-- LibSharedMedia hands out: a stored path is looked up among the registered
-- sounds and played as LSM:Fetch gives it, a path of no registered sound
-- (one typed in) through LSM:GetClientSoundPath. Unreal Azeroth plays an
-- addon's sound file only from a path of its own form, which the
-- LibSharedMedia-3.0 shipped with this addon builds; the stored data keeps
-- the standard "Interface\AddOns\..." form on both clients. Unreal Azeroth
-- plays Ogg Vorbis and WAV, not MP3.
--
-- Not ported: the sound channel (always "Master"), "Sound by Kit ID", and
-- "Stop Sound" with its fade-out -- neither client can stop a sound once it
-- plays. "Loop" plays the sound again every `sound_repeat` seconds until the
-- aura hides or another sound of the aura starts; a condition's "Stop" ends
-- the repetition, the sound playing at the moment runs to its end. One
-- repetition per aura, as WeakAuras keeps one per region.
--
-- As in WeakAuras, nothing plays while the options window is open, and
-- nothing in the first LOGIN_SQUELCH seconds after entering the world (an
-- aura already active at login would otherwise sound on every reload); a
-- loop started meanwhile sounds from its next repetition on.

local PA, L = unpack(PunyAuras)

PA.CUSTOM_SOUND = " custom"

local SOUND_FOLDER = "Interface\\AddOns\\PunyAuras\\Media\\Sounds\\"
local LOGIN_SQUELCH = 10

-- { LibSharedMedia name, file in Media/Sounds }, WeakAuras' order.
local SOUNDS = {
	{ "Heartbeat Single", "PunyAurasHeartbeatSingle.ogg" },
	{ "Batman Punch", "PunyAurasBatmanPunch.ogg" },
	{ "Bike Horn", "PunyAurasBikeHorn.ogg" },
	{ "Boxing Arena Gong", "PunyAurasBoxingArenaSound.ogg" },
	{ "Bleat", "PunyAurasBleat.ogg" },
	{ "Cat Meow", "PunyAurasCatMeow2.ogg" },
	{ "Kitten Meow", "PunyAurasKittenMeow.ogg" },
	{ "Robot Blip", "PunyAurasRobotBlip.ogg" },
	{ "Sharp Punch", "PunyAurasSharpPunch.ogg" },
	{ "Water Drop", "PunyAurasWaterDrop.ogg" },
	{ "Air Horn", "PunyAurasAirHorn.ogg" },
	{ "Applause", "PunyAurasApplause.ogg" },
	{ "Banana Peel Slip", "PunyAurasBananaPeelSlip.ogg" },
	{ "Blast", "PunyAurasBlast.ogg" },
	{ "Cartoon Voice Baritone", "PunyAurasCartoonVoiceBaritone.ogg" },
	{ "Cartoon Walking", "PunyAurasCartoonWalking.ogg" },
	{ "Cow Mooing", "PunyAurasCowMooing.ogg" },
	{ "Ringing Phone", "PunyAurasRingingPhone.ogg" },
	{ "Roaring Lion", "PunyAurasRoaringLion.ogg" },
	{ "Shotgun", "PunyAurasShotgun.ogg" },
	{ "Squish Fart", "PunyAurasSquishFart.ogg" },
	{ "Temple Bell", "PunyAurasTempleBellHuge.ogg" },
	{ "Torch", "PunyAurasTorch.ogg" },
	{ "Warning Siren", "PunyAurasWarningSiren.ogg" },
	{ "Sheep Blerping", "PunyAurasSheepBleat.ogg" },
	{ "Rooster Chicken Call", "PunyAurasRoosterChickenCalls.ogg" },
	{ "Goat Bleeting", "PunyAurasGoatBleating.ogg" },
	{ "Acoustic Guitar", "PunyAurasAcousticGuitar.ogg" },
	{ "Synth Chord", "PunyAurasSynthChord.ogg" },
	{ "Chicken Alarm", "PunyAurasChickenAlarm.ogg" },
	{ "Xylophone", "PunyAurasXylophone.ogg" },
	{ "Drums", "PunyAurasDrums.ogg" },
	{ "Tada Fanfare", "PunyAurasTadaFanfare.ogg" },
	{ "Squeaky Toy Short", "PunyAurasSqueakyToyShort.ogg" },
	{ "Error Beep", "PunyAurasErrorBeep.ogg" },
	{ "Oh No", "PunyAurasOhNo.ogg" },
	{ "Double Whoosh", "PunyAurasDoubleWhoosh.ogg" },
	{ "Brass", "PunyAurasBrass.ogg" },
	{ "Glass", "PunyAurasGlass.ogg" },
	{ "Voice: Adds", "PunyAurasAdds.ogg" },
	{ "Voice: Boss", "PunyAurasBoss.ogg" },
	{ "Voice: Circle", "PunyAurasCircle.ogg" },
	{ "Voice: Cross", "PunyAurasCross.ogg" },
	{ "Voice: Diamond", "PunyAurasDiamond.ogg" },
	{ "Voice: Don't Release", "PunyAurasDontRelease.ogg" },
	{ "Voice: Empowered", "PunyAurasEmpowered.ogg" },
	{ "Voice: Focus", "PunyAurasFocus.ogg" },
	{ "Voice: Idiot", "PunyAurasIdiot.ogg" },
	{ "Voice: Left", "PunyAurasLeft.ogg" },
	{ "Voice: Moon", "PunyAurasMoon.ogg" },
	{ "Voice: Next", "PunyAurasNext.ogg" },
	{ "Voice: Portal", "PunyAurasPortal.ogg" },
	{ "Voice: Protected", "PunyAurasProtected.ogg" },
	{ "Voice: Release", "PunyAurasRelease.ogg" },
	{ "Voice: Right", "PunyAurasRight.ogg" },
	{ "Voice: Run Away", "PunyAurasRunAway.ogg" },
	{ "Voice: Skull", "PunyAurasSkull.ogg" },
	{ "Voice: Spread", "PunyAurasSpread.ogg" },
	{ "Voice: Square", "PunyAurasSquare.ogg" },
	{ "Voice: Stack", "PunyAurasStack.ogg" },
	{ "Voice: Star", "PunyAurasStar.ogg" },
	{ "Voice: Switch", "PunyAurasSwitch.ogg" },
	{ "Voice: Taunt", "PunyAurasTaunt.ogg" },
	{ "Voice: Triangle", "PunyAurasTriangle.ogg" },
	{ "Aggro", "PunyAurasAggro.ogg" },
	{ "Arrow Swoosh", "PunyAurasArrow_Swoosh.ogg" },
	{ "Bam", "PunyAurasBam.ogg" },
	{ "Polar Bear", "PunyAurasBear_polar.ogg" },
	{ "Big Kiss", "PunyAurasBigkiss.ogg" },
	{ "Bite", "PunyAurasBITE.ogg" },
	{ "Burp", "PunyAurasBurp4.ogg" },
	{ "Cat", "PunyAurasCat2.ogg" },
	{ "Chant Major 2nd", "PunyAurasChant2.ogg" },
	{ "Chant Minor 3rd", "PunyAurasChant4.ogg" },
	{ "Chimes", "PunyAurasChimes.ogg" },
	{ "Cookie Monster", "PunyAurasCookie.ogg" },
	{ "Electrical Spark", "PunyAurasESPARK1.ogg" },
	{ "Fireball", "PunyAurasFireball.ogg" },
	{ "Gasp", "PunyAurasGasp.ogg" },
	{ "Heartbeat", "PunyAurasHeartbeat.ogg" },
	{ "Hiccup", "PunyAurasHic3.ogg" },
	{ "Huh?", "PunyAurasHuh_1.ogg" },
	{ "Hurricane", "PunyAurasHurricane.ogg" },
	{ "Hyena", "PunyAurasHyena.ogg" },
	{ "Kaching", "PunyAurasKaching.ogg" },
	{ "Moan", "PunyAurasMoan.ogg" },
	{ "Panther", "PunyAurasPanther1.ogg" },
	{ "Phone", "PunyAurasPhone.ogg" },
	{ "Punch", "PunyAurasPUNCH.ogg" },
	{ "Rain", "PunyAurasRainroof.ogg" },
	{ "Rocket", "PunyAurasRocket.ogg" },
	{ "Ship's Whistle", "PunyAurasShipswhistle.ogg" },
	{ "Gunshot", "PunyAurasShot.ogg" },
	{ "Snake Attack", "PunyAurasSnakeatt.ogg" },
	{ "Sneeze", "PunyAurasSneeze.ogg" },
	{ "Sonar", "PunyAurasSonar.ogg" },
	{ "Splash", "PunyAurasSplash.ogg" },
	{ "Squeaky Toy", "PunyAurasSqueakypig.ogg" },
	{ "Sword Ring", "PunyAurasSwordecho.ogg" },
	{ "Throwing Knife", "PunyAurasThrowknife.ogg" },
	{ "Thunder", "PunyAurasThunder.ogg" },
	{ "Wicked Male Laugh", "PunyAurasWickedmalelaugh1.ogg" },
	{ "Wilhelm Scream", "PunyAurasWilhelm.ogg" },
	{ "Wicked Female Laugh", "PunyAurasWlaugh.ogg" },
	{ "Wolf Howl", "PunyAurasWolf5.ogg" },
	{ "Yeehaw", "PunyAurasYeehaw.ogg" },
}

local function LSM()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- The time before which no sound plays; reset on the first
-- PLAYER_ENTERING_WORLD.
local squelchUntil = 0

-- The repeating sounds, keyed by aura id: { options, interval, nextTime }.
local loops = {}
local driver

-- `path` as the running client plays it (see the header): what
-- LibSharedMedia fetches for the sound registered with this path, else the
-- path through LibSharedMedia's client rewrite. A LibSharedMedia without
-- that rewrite leaves the path as it is.
local function ClientPath(path)
	local lsm = LSM()
	if not lsm then return path end
	local hash = lsm:HashTable("sound")
	if hash then
		local name, registered
		for name, registered in pairs(hash) do
			if registered == path then
				return lsm:Fetch("sound", name, true) or path
			end
		end
	end
	if lsm.GetClientSoundPath then return lsm:GetClientSoundPath(path) end
	return path
end

-- Plays the sound file `path` at once (the options' preview, and every
-- sound an aura plays).
function PA:PlaySoundPath(path)
	if type(path) ~= "string" or path == "" or path == self.CUSTOM_SOUND then return end
	pcall(PlaySoundFile, ClientPath(path), "Master")
end

-- The file the sound options `options` choose.
local function SoundPath(options)
	if options.sound == PA.CUSTOM_SOUND then return options.sound_path end
	return options.sound
end

-- WeakAuras' hasSound: a "Stop", or a sound to play.
local function HasSound(options)
	if options.sound_type == "Stop" then return true end
	local path = SoundPath(options)
	return type(path) == "string" and path ~= ""
end

local function OptionsOpen()
	return PA.IsOptionsOpen and PA:IsOptionsOpen()
end

-- WeakAuras' SoundPlayHelper: one play of a sound or a repetition.
local function PlayOnce(options)
	if options.sound_type == "Stop" then return end
	if OptionsOpen() or GetTime() < squelchUntil then return end
	PA:PlaySoundPath(SoundPath(options))
end

-- Plays the repetitions that are due; one whose aura is no longer active
-- ends. The script is removed while nothing repeats.
local function OnUpdate()
	local now = GetTime()
	local any = false
	local id, loop
	for id, loop in pairs(loops) do
		local state = PA.auraStates and PA.auraStates[id]
		if not (state and state.active) then
			loops[id] = nil
		else
			any = true
			if now >= loop.nextTime then
				loop.nextTime = now + loop.interval
				PlayOnce(loop.options)
			end
		end
	end
	if not any then driver:SetScript("OnUpdate", nil) end
end

-- Ends the repetition of the aura `id`'s sound (WeakAuras' SoundRepeatStop).
function PA:SoundRepeatStop(id)
	loops[id] = nil
end

-- Plays the sound `options` describe for the aura `id` (an action's or a
-- condition's "Sound" change), and repeats it for a loop (WeakAuras'
-- SoundPlay). Any repetition of the aura's earlier sound ends.
function PA:SoundPlay(id, options)
	if type(options) ~= "table" or OptionsOpen() or not HasSound(options) then return end
	self:SoundRepeatStop(id)
	PlayOnce(options)
	local interval = tonumber(options.sound_repeat)
	if (options.do_loop or options.sound_type == "Loop") and interval and interval > 0 then
		loops[id] = { options = options, interval = interval, nextTime = GetTime() + interval }
		if driver then driver:SetScript("OnUpdate", OnUpdate) end
	end
end

-- Every sound a sound option offers, keyed by path (WeakAuras'
-- sound_types): LibSharedMedia's sounds -- this addon's and any other
-- addon's -- and "Custom". The leading space sorts "Custom" first.
function PA:GetSoundValues()
	local values = { [self.CUSTOM_SOUND] = " " .. L["Custom"] }
	local lsm = LSM()
	local hash = lsm and lsm:HashTable("sound")
	if hash then
		local name, path
		for name, path in pairs(hash) do
			if type(path) == "string" then values[path] = name end
		end
	end
	return values
end

function PA:InitializeSounds()
	local lsm = LSM()
	if lsm then
		local i
		for i = 1, PunyAuras.Compat.getn(SOUNDS) do
			lsm:Register("sound", SOUNDS[i][1], SOUND_FOLDER .. SOUNDS[i][2])
		end
	end

	squelchUntil = GetTime() + LOGIN_SQUELCH
	local entered = false
	driver = CreateFrame("Frame")
	pcall(driver.RegisterEvent, driver, "PLAYER_ENTERING_WORLD")
	driver:SetScript("OnEvent", function()
		if entered then return end
		entered = true
		squelchUntil = GetTime() + LOGIN_SQUELCH
	end)
	if next(loops) then driver:SetScript("OnUpdate", OnUpdate) end
end
