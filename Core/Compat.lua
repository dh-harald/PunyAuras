-- PunyAuras.Compat: Lua 5.0 / 5.1 shim layer.
--
-- WoW 1.12.1 runs Lua 5.0, Unreal Azeroth (UA) runs Lua 5.1. Every helper
-- prefers the native 5.1 function and falls back to a 5.0-safe
-- implementation only when it is missing. Nothing here touches the global
-- `string`/`table`/`math` libraries, so another addon's environment is never
-- clobbered. Ported from ElvUI-UA's Core/Compat.lua.
--
-- Three constructs fail to PARSE on the 1.12.1 client's Lua 5.0.3, so they
-- must not appear in any file loaded on both clients, not even in an
-- unreachable branch:
--   1. `...` as an expression (`return ...`, `f(...)`, `select('#', ...)`).
--      Declare vararg functions as `function(...)` and read the implicit
--      `arg` table; use Compat.argCount/Compat.argUnpack instead of select.
--   2. The `#` length operator: use Compat.getn / string.len.
--   3. The `%` modulo operator: use Compat.mod.
-- Lua 5.0 also caps a function at 32 upvalues, closures inside it included.
--
-- The 1.12.1 client's standard library is trimmed as well (no string.match,
-- string.gmatch, math.modf, math.fmod, math.huge, table.wipe, ...). Another
-- addon's global polyfill can hide a missing function, so route every such
-- call through here.

PunyAuras = PunyAuras or {}
PunyAuras.Compat = PunyAuras.Compat or {}

local Compat = PunyAuras.Compat

-- Diagnostic only: feature-detect the specific function instead of
-- branching on this.
Compat.isLua50 = (string.match == nil)

-- Which client, not which Lua; only for places where the same working API
-- must be driven differently on the two clients. `GetUECvar` is the Unreal
-- engine's cvar accessor and exists on no Blizzard client; 5875 is UA's
-- interface number. Probe taken from LibConfig-1.0's DetectUA.
Compat.isUA = false
if GetUECvar then
	Compat.isUA = true
elseif type(GetBuildInfo) == "function" then
	local okBuild, _, _, _, tocversion = pcall(GetBuildInfo)
	if okBuild and tonumber(tocversion) == 5875 then
		Compat.isUA = true
	end
end

-- string.match: absent in Lua 5.0.
if string.match then
	Compat.match = string.match
else
	function Compat.match(str, pattern, index)
		if type(str) ~= "string" then
			error(string.format("bad argument #1 to 'match' (string expected, got %s)", type(str)), 2)
		end

		local results = { string.find(str, pattern, index) }
		local start, finish = results[1], results[2]
		if not start then
			return nil
		end

		if results[3] == nil then
			return string.sub(str, start, finish)
		end

		table.remove(results, 1)
		table.remove(results, 1)
		return unpack(results)
	end
end

-- string.gmatch: Lua 5.0 has the same iterator as string.gfind.
Compat.gmatch = string.gmatch or string.gfind

-- Array length without the `#` operator.
Compat.getn = table.getn or function(t)
	local n = 0
	while t[n + 1] ~= nil do
		n = n + 1
	end
	return n
end

-- select() replacements, operating on an already captured `arg` table.
function Compat.argCount(argTable)
	return argTable.n or Compat.getn(argTable)
end

function Compat.argUnpack(argTable, i, j)
	return unpack(argTable, i or 1, j or Compat.argCount(argTable))
end

-- Modulo without the `%` operator. math.mod is 5.0; 5.1 may lack it.
Compat.mod = math.mod or function(a, b)
	return a - math.floor(a / b) * b
end

-- math.modf: missing on the 1.12.1 client. Truncates toward zero and
-- returns the integer part and the signed fractional remainder.
Compat.modf = math.modf or function(value)
	value = tonumber(value)
	if type(value) ~= "number" then
		error("bad argument #1 to 'modf' (number expected)", 2)
	end

	local int = value >= 0 and math.floor(value) or math.ceil(value)

	return int, value - int
end

-- Yes/no API returns normalized to a real boolean: nil, false and 0 are
-- false. The 1.12.1 client returns 1/nil or 1/0 from flag getters, UA
-- returns true/false, so neither `== 1` nor `not x` is correct on both.
-- Only for flags: not for numeric values, tri-state returns such as
-- IsActionInRange (1 / 0 / nil), or GetCVar strings ("0" is truthy).
function Compat.bool(value)
	return value ~= nil and value ~= false and value ~= 0
end
