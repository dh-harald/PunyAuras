-- Aura export and import (WeakAuras Transmission.lua and the import side of
-- WeakAurasOptions OptionsFrames/Update.lua, GPLv2), in PunyAuras' own string
-- format: "!PA:1!" followed by the transmission table serialized with
-- AceSerializer-3.0, compressed with LibDeflate (raw deflate, level 9) and
-- written in LibDeflate's printable alphabet (letters, digits, "(", ")"):
-- one line without spaces.
--
-- The transmission table is WeakAuras' own: { m = "d", d = <aura>, c =
-- <children>, v = TRANSMIT_VERSION, s = <PunyAuras version> }. Groups do not
-- nest, so as in WeakAuras' version 1421 a group's children travel as the
-- list `c` in the group's order, and `parent` / `controlledChildren` are left
-- out; the import rebuilds them.
--
-- Every exported aura carries a `uid`, WeakAuras' GenerateUniqueID (eleven
-- characters of its 64-character alphabet), given on the first export and
-- kept in the saved data. An import names its auras like WeakAuras' import of
-- a new aura: an id already in use gets the next free "<id> 2", "<id> 3"
-- (PA:FindUnusedId), and a uid already in use is replaced (EnsureUniqueUid).
-- Importing an aura whose uid is installed creates a copy, which is what
-- WeakAuras' "Import as Copy" does; its "Update" choice is not offered.
-- Manual icons travel in the path form both clients draw
-- (PA:PortableIconPath): on export, and on import through PA:ValidateData.
--
-- Two versions guard an import. The number in "!PA:<n>!" is the string's
-- format: a string of any other format is refused. `s` is the version of
-- the PunyAuras that exported it: an export of a newer PunyAuras than the
-- one installed is refused with a request to update, an older one is
-- imported. Only release versions ("1.2.3") are compared; a working copy's
-- "dev" is compared with nothing.

local PA, L = unpack(PunyAuras)
local Compat = PunyAuras.Compat

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local FORMAT = 1
local PREFIX = "!PA:" .. FORMAT .. "!"
local TRANSMIT_VERSION = 1
local DEFLATE_CONFIG = { level = 9 }

-- The parts of a release version ("1.2.3", or "v1.2.3" as tagged), or nil
-- for anything else.
local function ReleaseVersion(version)
	if type(version) ~= "string" then return nil end
	local _, _, major, minor, patch = string.find(version, "^v?(%d+)%.(%d+)%.(%d+)$")
	if not major then return nil end
	return { tonumber(major), tonumber(minor), tonumber(patch) }
end

-- Whether release version `a` is newer than release version `b`; false
-- when either is not a release version.
function PA:IsNewerVersion(a, b)
	local va, vb = ReleaseVersion(a), ReleaseVersion(b)
	if not (va and vb) then return false end
	local i
	for i = 1, 3 do
		if va[i] ~= vb[i] then return va[i] > vb[i] end
	end
	return false
end

-- WeakAuras' bytetoB64, the alphabet of its uids.
local UID_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"

-- The fields an exported aura leaves out (WeakAuras'
-- non_transmissable_fields, as far as they exist here).
local NON_TRANSMISSABLE = { controlledChildren = true, parent = true }

function PA:GenerateUniqueID()
	local chars = {}
	local i
	for i = 1, 11 do
		local n = math.random(1, 64)
		chars[i] = string.sub(UID_CHARS, n, n)
	end
	return table.concat(chars)
end

-- The id of the installed aura with `uid`, if any.
function PA:GetIdByUID(uid)
	if type(uid) ~= "string" then return nil end
	local id, data
	for id, data in pairs(self.db.global.displays) do
		if data.uid == uid then return id end
	end
end

-- The transmission string of any table.
function PA:TableToString(t)
	local serialized = AceSerializer:Serialize(t)
	local compressed = LibDeflate:CompressDeflate(serialized, DEFLATE_CONFIG)
	return PREFIX .. LibDeflate:EncodeForPrint(compressed)
end

-- The table of a transmission string, or nil and the reason it cannot be
-- read (WeakAuras' StringToTable messages). Space around the string, and
-- line breaks a paste may add inside it, are ignored.
function PA:StringToTable(text)
	if type(text) ~= "string" then return nil, L["Invalid import data."] end
	text = string.gsub(text, "%s+", "")
	local _, _, version, encoded = string.find(text, "^!PA:(%d+)!(.+)$")
	if not version then
		return nil, L["Not a PunyAuras import string."]
	end
	version = tonumber(version)
	if version > FORMAT then
		return nil, L["This import string needs a newer version of PunyAuras. Please update the addon."]
	elseif version ~= FORMAT then
		return nil, L["This import string is in a format this version of PunyAuras cannot read."]
	end

	local decoded = LibDeflate:DecodeForPrint(encoded)
	if not decoded then return nil, L["Error decoding."] end
	local decompressed = LibDeflate:DecompressDeflate(decoded)
	if not decompressed then return nil, L["Error decompressing"] end
	local ok, result = AceSerializer:Deserialize(decompressed)
	if not ok or type(result) ~= "table" then return nil, L["Error deserializing"] end
	return result
end

-- A copy of `data` as it is exported.
local function TransmitCopy(data)
	local copy = PA.DeepCopy(data)
	local key
	for key in pairs(NON_TRANSMISSABLE) do
		copy[key] = nil
	end
	PA:PortableIcons(copy)
	return copy
end

-- The export string of aura `id`, a group with its children. Gives the
-- aura, and every child, a uid if it has none, and a child whose uid another
-- child has already a new one (WeakAuras' DisplayToString).
function PA:DisplayToString(id)
	local data = self:GetData(id)
	if not data then return "" end
	data.uid = data.uid or self:GenerateUniqueID()

	local transmit = {
		m = "d",
		d = TransmitCopy(data),
		v = TRANSMIT_VERSION,
		s = self.version,
	}
	if self:IsGroup(data) then
		transmit.c = {}
		local uids = { [data.uid] = true }
		local i
		for i = 1, Compat.getn(data.controlledChildren) do
			local child = self:GetData(data.controlledChildren[i])
			if child then
				if not child.uid or uids[child.uid] then
					child.uid = self:GenerateUniqueID()
				end
				uids[child.uid] = true
				table.insert(transmit.c, TransmitCopy(child))
			end
		end
	end
	return self:TableToString(transmit)
end

-- Whether `data` can be imported, at the top or (`asChild`) as a group's
-- child: a table with a region type that exists here, a group only at the
-- top.
local function ValidImportData(data, asChild)
	if type(data) ~= "table" or not PA.regionTypes[data.regionType or ""] then
		return false
	end
	if asChild and PA:IsGroup(data) then return false end
	return true
end

-- Reads an import string. Returns the pending import, { data, children },
-- or nil and the reason it cannot be imported.
function PA:ParseImport(text)
	local received, err = self:StringToTable(text)
	if not received then return nil, err end
	if received.m ~= "d" or type(received.d) ~= "table" then
		return nil, L["Invalid import data."]
	end
	if self:IsNewerVersion(received.s, self.version) then
		return nil, string.format(
			L["This aura was exported by PunyAuras %s, newer than yours (%s). Please update the addon."],
			tostring(received.s), tostring(self.version))
	end
	local data = received.d
	if not ValidImportData(data, false) then
		return nil, string.format(L["Unknown aura type: %s"], tostring(data.regionType))
	end

	local children = {}
	if self:IsGroup(data) and type(received.c) == "table" then
		local i
		for i = 1, Compat.getn(received.c) do
			local child = received.c[i]
			if not ValidImportData(child, true) then
				return nil, string.format(L["Unknown aura type: %s"],
					tostring(type(child) == "table" and child.regionType or child))
			end
			table.insert(children, child)
		end
	end
	return { data = data, children = children }
end

-- The id of the installed aura the pending import's aura is a copy of (same
-- uid), if any.
function PA:FindImportMatch(pending)
	return self:GetIdByUID(pending.data.uid)
end

-- Adds one imported aura under a free id, completed from its region type's
-- defaults (settings added after the export was made) and validated.
local function AddImported(data)
	data.parent = nil
	data.controlledChildren = nil
	if type(data.uid) ~= "string" or PA:GetIdByUID(data.uid) then
		data.uid = PA:GenerateUniqueID()
	end
	local key, value
	for key, value in pairs(PA.regionTypes[data.regionType].default) do
		if data[key] == nil then data[key] = PA.DeepCopy(value) end
	end
	if type(data.id) ~= "string" or data.id == "" then data.id = L["New"] end
	data.id = PA:FindUnusedId(data.id)
	PA:ValidateData(data)
	PA.db.global.displays[data.id] = data
end

-- Installs a pending import (PA:ParseImport) and returns the id of its
-- aura: the group first, then its children in order, each under a free id.
function PA:ImportPending(pending)
	local data = pending.data
	AddImported(data)
	if self:IsGroup(data) then
		local i
		for i = 1, Compat.getn(pending.children) do
			local child = pending.children[i]
			AddImported(child)
			child.parent = data.id
			table.insert(data.controlledChildren, child.id)
		end
	end
	self:RefreshRegion(data.id)
	self:ScheduleTriggerUpdate()
	return data.id
end
