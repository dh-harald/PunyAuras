-- Name -> icon cache, account-wide. Every aura whose name the trigger scanner
-- reads and every spell in the player's spellbook is stored here, so an aura
-- trigger showing a missing aura can still show that aura's icon (WeakAuras
-- looks it up from the spell name), and the icon picker can offer auras seen
-- before.

local PA, L, P, G = unpack(PunyAuras)
local Compat = PunyAuras.Compat

-- [lowercased name] = { name = name as seen, icon = texture path }
G.iconCache = {}

function PA:CacheIcon(name, icon)
	if type(name) ~= "string" or name == "" then return end
	if type(icon) ~= "string" or icon == "" then return end
	local cache = self.db.global.iconCache
	local key = string.lower(name)
	local entry = cache[key]
	if entry and entry.name == name and entry.icon == icon then return end
	cache[key] = { name = name, icon = icon }
end

function PA:GetCachedIcon(name)
	if type(name) ~= "string" then return nil end
	local entry = self.db.global.iconCache[string.lower(name)]
	return entry and entry.icon
end

-- Every cached entry, sorted by name, for the icon picker.
function PA:GetCachedIcons()
	local list = {}
	local key, entry
	for key, entry in pairs(self.db.global.iconCache) do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

function PA:CacheSpellbook()
	local i = 1
	while true do
		local ok, name = pcall(GetSpellName, i, "spell")
		if not ok or not name then break end
		local okTexture, texture = pcall(GetSpellTexture, i, "spell")
		if okTexture then self:CacheIcon(name, texture) end
		i = i + 1
	end
end
