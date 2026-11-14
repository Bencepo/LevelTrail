-- Minimal World of Warcraft environment for running addon files outside the game.
-- Only the APIs listed here exist. Any other global is nil, as a missing API is in the
-- game, so a typo'd or unknown function fails loudly when it is called. Frames and
-- timers are "stubs" (an allow-listed object: any field and any call returns the stub
-- again) so frame setup at load time does nothing. Tests set what they need (items,
-- unit values, saved variables) before or after loading.

local M = {}

local stub
stub = setmetatable({}, {
	__index = function() return stub end,
	__call = function() return stub end,
	__newindex = function() end,
})
M.stub = stub

-- items[id] = { name, quality, ilvl, minLevel, classID, sell, stack }
local function ItemInfo(items, item)
	local id = type(item) == "number" and item or tonumber(tostring(item or ""):match("item:(%d+)"))
	local it = id and items[id]
	if not it then return nil end
	local link = "|cff1eff00|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r"
	return it.name, link, it.quality or 1, it.ilvl or 1, it.minLevel or 1, "", "", it.stack or 1, "", 0,
		it.sell or 0, it.classID or 15
end

-- Real enUS client strings (GlobalStrings.lua).
local STRINGS = {
	COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience.",
	ERR_ZONE_EXPLORED_XP = "Discovered %s: %d experience gained",
	LOOT_ITEM_SELF = "You receive loot: %s.",
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
}
M.STRINGS = STRINGS

-- Loads the addon files (in order) into a fresh environment. Returns ns and the environment.
-- env.now is the clock (time()); tests move it forward.
function M.Load(addon, files, setup)
	local env, items = {}, {}
	env._G = env
	env.items = items
	env.now = 1800000000
	local function info(item) return ItemInfo(items, item) end
	env.C_Item = { GetItemInfo = info, GetItemID = function(loc) return loc and loc.id end }
	env.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
	env.C_Timer = { After = function() end, NewTicker = function() return stub end }
	env.CreateFrame = function() return stub end
	env.UIParent = stub
	env.UISpecialFrames = {}
	env.SlashCmdList = {}
	env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
	env.GetLocale = function() return "enUS" end
	env.time = function() return env.now end
	env.date = function(fmt, t) return os.date(fmt, t or env.now) end
	env.GetTime = os.clock
	env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	env.tinsert, env.tremove = table.insert, table.remove
	env.print = function() end
	env.UnitName = function() return "Tester" end
	env.GetRealmName = function() return "Realm" end
	env.GetMoney = function() return env.money or 0 end
	env.GetMaxPlayerLevel = function() return 60 end
	env.UnitLevel = function() return env.level or 10 end
	env.UnitXP = function() return env.xp or 0 end
	env.UnitXPMax = function() return env.xpMax or 7600 end
	env.GetRealZoneText = function() return env.zone or "Durotar" end
	env.GetSubZoneText = function() return "" end
	env.IsInInstance = function() return env.inInstance or false, env.instanceType or "none" end
	env.GetInstanceInfo = function() return env.instanceName end
	env.UnitIsDeadOrGhost = function() return env.dead or false end
	for k, v in pairs(STRINGS) do env[k] = v end
	if setup then setup(env) end
	-- Lua's own library (string, table, math, pairs, ...) and nothing else
	setmetatable(env, { __index = function(_, k)
		if k == "unpack" then return unpack or rawget(table, "unpack") end
		return _G[k]
	end })
	local ns = {}
	for _, file in ipairs(files) do
		local chunk
		if setfenv then -- Lua 5.1, like the game
			chunk = assert(loadfile(file))
			setfenv(chunk, env)
		else
			chunk = assert(loadfile(file, "t", env))
		end
		chunk(addon, ns)
	end
	return ns, env
end

return M
