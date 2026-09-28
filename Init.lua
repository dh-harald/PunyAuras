-- PunyAuras core bootstrap.
--
-- The global `PunyAuras` table is the engine every other file reaches the
-- addon through, as `local PA, L, P, G = unpack(PunyAuras)`:
--   [1] the AceAddon object, [2] the AceLocale table,
--   [3] profile defaults, [4] global defaults.
-- The 1.12.1 client passes no addon name/private table to a file chunk
-- (and `...` at chunk level does not parse on Lua 5.0), so a global engine
-- table is the only way to share state between files.

PunyAuras = PunyAuras or {}

local AddOnName = "PunyAuras"
local Engine = PunyAuras

local AddOn = LibStub("AceAddon-3.0"):NewAddon(AddOnName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
local Locale = LibStub("AceLocale-3.0"):GetLocale(AddOnName)

AddOn.noop = function() end

-- The packager replaces the .toc's "@project-version@" with the release tag
-- ("v1.2.3"); an unpackaged working copy reports "dev".
local version = GetAddOnMetadata(AddOnName, "Version")
if version and string.sub(version, 1, 1) == "v" then
	AddOn.version = string.sub(version, 2)
else
	AddOn.version = "dev"
end

-- AceDB defaults. Files loaded after this one fill them in at file load time,
-- which is before ADDON_LOADED drives OnInitialize.
AddOn.defaults = { profile = {}, global = {} }

Engine[1] = AddOn
Engine[2] = Locale
Engine[3] = AddOn.defaults.profile
Engine[4] = AddOn.defaults.global

function AddOn:OnInitialize()
	-- `true`: characters without an explicit profile share "Default".
	self.db = LibStub("AceDB-3.0"):New("PunyAurasDB", self.defaults, true)
	self:ValidateAllData()

	self:InitializeMinimapIcon()
	self:InitializeOptions()
	self:InitializeTriggers()

	-- /wa is WeakAuras' own command; /pa is its PunyAuras counterpart.
	self:RegisterChatCommand("pa", "ToggleOptions")
	self:RegisterChatCommand("punyauras", "ToggleOptions")

	self:Print(Locale["Initialized."])
end

function AddOn:OnEnable()
end
