-- LevelTrail
-- Copyright (c) 2026 Bencepo. All rights reserved. See LICENSE.
--
-- Records a character's leveling into SavedVariables: a snapshot of the character
-- (gold, bags, gear, professions, quests, talents, reputation) plus a history of
-- level splits, XP sources, play sessions, deaths, gold, repairs and time/XP per zone.
-- A small tracker window (/trail hud) shows the pace: XP per hour and the time to the
-- next level and to the level cap.
-- /trail shows everything as JSON to copy into a companion app.
-- The game writes the file on /reload and on logout:
--   WTF\Account\<ACCOUNT>\SavedVariables\LevelTrail.lua
-- Nothing here sends input to the game; it only reads.
LevelTrailDB = LevelTrailDB or {}

local ADDON, ns = ...
ns = ns or {}
local VERSION = 9 -- data version
local BUG_URL = "https://github.com/Bencepo/LevelTrail/issues/new/choose"
local GetMetadata = C_AddOns.GetAddOnMetadata

-- Item and money functions live in C_Item / C_CurrencyInfo on current clients. The old
-- globals are only fallbacks for clients without them and are read in this one place.
---@diagnostic disable: deprecated
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local GetCoinTextureString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
---@diagnostic enable: deprecated
local ADDON_VERSION = GetMetadata and GetMetadata(ADDON, "Version") or ""
if ADDON_VERSION == "" or ADDON_VERSION:find("^@") then ADDON_VERSION = "dev" end
local TITLE = "LevelTrail " .. ADDON_VERSION

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h end
  return nil
end

---------------------------------------------------------------- XP table and level cap
-- XP needed for each level up to 60 (Classic table). If the game reports a different
-- value for the current level, the other levels are scaled by the same factor.
local XP_TABLE = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
  16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
  50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500,
  123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }

local function maxLevel()
  local m = try(GetMaxPlayerLevel)
  if type(m) == "number" and m > 0 then return m end
  return 60
end

local function xpForLevel(level, scale)
  local v = XP_TABLE[level]
  if not v then return nil end
  return math.floor(v * (scale or 1) + 0.5)
end

-- XP values are 0 for a moment at login and logout; at the level cap UnitXPMax may stay 0.
local function xpReady()
  local level = UnitLevel("player") or 0
  if level == 0 then return false end
  return (UnitXPMax("player") or 0) > 0 or level >= maxLevel()
end

-- Last character bag: 4 on Classic clients, 5 where a reagent bag exists. Bank bags follow it.
local function lastBagID()
  return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local function charKey()
  local name = UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or "?"
  return name .. "-" .. realm, name, realm
end

local function store()
  local key = charKey()
  LevelTrailDB[key] = LevelTrailDB[key] or {}
  return LevelTrailDB[key]
end

---------------------------------------------------------------- online clock and level splits
-- Online time is counted by the addon itself (once a minute while logged in), so it
-- starts at the install. A level the addon did not see from its start is "partial".
local clockLast, clockZone

local function currentZone()
  local z = GetRealZoneText and GetRealZoneText() or ""
  if z == "" then return nil end
  return z
end

-- Per-zone totals: online seconds, XP and deaths.
local function zoneRec(s, zone)
  if not zone then return nil end
  s.zones = s.zones or {}
  local z = s.zones[zone]
  if not z then
    z = { time = 0, xp = 0, deaths = 0, first = date("%Y-%m-%d") }
    s.zones[zone] = z
  end
  return z
end

-- Per zone and level: online seconds (t) and XP (x), for the best zone per level range.
local function zoneLevelRec(s, zone, level)
  level = tonumber(level)
  if not zone or not level or level < 1 then return nil end
  s.zoneLevels = s.zoneLevels or {}
  local z = s.zoneLevels[zone] or {}
  s.zoneLevels[zone] = z
  local r = z[level]
  if not r then r = { t = 0, x = 0 }; z[level] = r end
  return r
end

local sessionTouch -- defined with the sessions below

local function clockTick()
  local s = store()
  local now = time()
  if clockLast then
    local d = now - clockLast
    if d > 0 and d <= 600 then
      s.online = (s.online or 0) + d
      local z = zoneRec(s, clockZone)
      if z then z.time = z.time + d; z.last = date("%Y-%m-%d") end
      local zl = zoneLevelRec(s, clockZone, UnitLevel("player"))
      if zl then zl.t = zl.t + d end
      -- a dungeon visit only runs on while the player is inside
      if s.dungeonRun and try(IsInInstance) then s.dungeonRun.last = now end
      -- being online keeps the play session going, XP or not
      if sessionTouch then pcall(sessionTouch) end
    end
  end
  clockLast = now
  clockZone = currentZone()
end

local function levelInit()
  local s = store()
  local L = UnitLevel("player") or 0
  if L == 0 then return end
  s.firstLevel = s.firstLevel or (s.splits and s.splits[1] and s.splits[1].level and s.splits[1].level - 1) or L
  if not s.levelSince or s.levelSince.level ~= L then
    s.levelSince = { level = L, online = s.online or 0, ts = time(), date = date("%Y-%m-%d %H:%M"), partial = true }
  end
end

local function onLevelUp(newLevel)
  clockTick()
  local s = store()
  newLevel = tonumber(newLevel) or UnitLevel("player")
  local since = s.levelSince
  s.splits = s.splits or {}
  local rec = { level = newLevel, date = date("%Y-%m-%d %H:%M"), ts = time(), online = s.online or 0 }
  if since and since.level == newLevel - 1 then
    rec.dur = (s.online or 0) - (since.online or 0)
    rec.partial = since.partial or nil
  end
  s.splits[#s.splits + 1] = rec
  s.levelSince = { level = newLevel, online = s.online or 0, ts = time(), date = rec.date }
end

---------------------------------------------------------------- XP sources
-- Quest XP comes with QUEST_TURNED_IN, kill and exploration XP from the game's own
-- (localized) chat lines. Everything else (e.g. profession or turn-in items) shows as
-- the difference to the total.
local function toPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local p = fmt:gsub("%%%%", "\1") -- a literal percent sign
  p = p:gsub("%%%d+%$", "%%")
  p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.-)")
  p = p:gsub("%%d", "(%%d+)")
  p = p:gsub("\1", "%%%%")
  return "^" .. p
end

local KILL_PATTERN = toPattern(COMBATLOG_XPGAIN_FIRSTPERSON)
local EXPLORE_PATTERN = toPattern(ERR_ZONE_EXPLORED_XP)

local function numberIn(msg, pattern)
  if not (msg and pattern) then return nil end
  local captures = { msg:match(pattern) }
  for _, c in ipairs(captures) do
    local n = tonumber(c)
    if n then return n end
  end
  return nil
end

local function addXP(level, field, amount)
  amount = tonumber(amount)
  if not amount or amount <= 0 then return end
  local s = store()
  local x = s.xpSources or { quest = 0, kill = 0, explore = 0, total = 0, byLevel = {} }
  s.xpSources = x
  x.byLevel = x.byLevel or {}
  x[field] = (x[field] or 0) + amount
  local key = tostring(level or UnitLevel("player") or 0)
  local b = x.byLevel[key] or { quest = 0, kill = 0, explore = 0, total = 0 }
  x.byLevel[key] = b
  b[field] = (b[field] or 0) + amount
  if field == "total" then
    local zone = currentZone()
    local z = zoneRec(s, zone)
    if z then z.xp = z.xp + amount end
    local zl = zoneLevelRec(s, zone, level or UnitLevel("player"))
    if zl then zl.x = zl.x + amount end
  end
end

---------------------------------------------------------------- counters (session recap and dungeon runs)
-- Kills (with XP), quests, deaths and loot value count for the running play session
-- and, inside an instance, for the running dungeon visit.
local function bump(field, n)
  n = tonumber(n) or 1
  local s = store()
  local cur = sessionTouch and sessionTouch()
  if cur then cur[field] = (cur[field] or 0) + n end
  if s.dungeonRun then s.dungeonRun[field] = (s.dungeonRun[field] or 0) + n end
end

-- Vendor value of looted items, from the game's own loot lines.
-- For an item the client has not cached yet it returns 0 plus the item ID and count,
-- so the value can be added once the item data arrives.
local LOOT_MULTI = toPattern(LOOT_ITEM_SELF_MULTIPLE)
local LOOT_SINGLE = toPattern(LOOT_ITEM_SELF)
local function lootValue(msg)
  if type(msg) ~= "string" then return 0 end
  local link, count
  if LOOT_MULTI then link, count = msg:match(LOOT_MULTI) end
  if not link and LOOT_SINGLE then link = msg:match(LOOT_SINGLE) end
  if not link then return 0 end
  count = tonumber(count) or 1
  if not GetItemInfo then return 0 end
  -- try() returns at most 8 values; the sell price is the 11th
  local r = { pcall(GetItemInfo, link) }
  if not r[1] then return 0 end
  if r[2] == nil then return 0, tonumber(link:match("item:(%d+)")), count end
  return (tonumber(r[12]) or 0) * count
end

-- Loot of uncached items: item ID -> count, valued on GET_ITEM_INFO_RECEIVED.
local lootPending = {}
local function lootQueue(id, count)
  if not id then return end
  lootPending[id] = (lootPending[id] or 0) + (count or 1)
  if C_Item and C_Item.RequestLoadItemDataByID then try(C_Item.RequestLoadItemDataByID, id) end
end

local function lootReceived(id, ok)
  local count = id and lootPending[id]
  if not count then return end
  lootPending[id] = nil
  if ok == false then return end
  local r = { pcall(GetItemInfo, id) }
  local v = r[1] and (tonumber(r[12]) or 0) * count or 0
  if v > 0 then bump("loot", v) end
end

---------------------------------------------------------------- dungeon runs
local function xpTotal(s) return (s.xpSources and s.xpSources.total) or 0 end

local function dungeonFinish(s)
  local run = s.dungeonRun
  if not run then return end
  s.dungeonRun = nil
  local stop = run.last or time()
  local minutes = math.floor((stop - run.start) / 60)
  if minutes < 2 then return end
  s.dungeons = s.dungeons or {}
  s.dungeons[#s.dungeons + 1] = { name = run.name, type = run.type, date = run.date, level = run.level,
    minutes = minutes, xp = xpTotal(s) - (run.xp0 or 0), copper = (GetMoney() or 0) - (run.copper0 or 0),
    kills = run.kills or 0, deaths = run.deaths or 0, loot = run.loot or 0 }
  while #s.dungeons > 50 do table.remove(s.dungeons, 1) end
end

local function dungeonCheck()
  local s = store()
  local inside, kind = try(IsInInstance)
  local name = inside and (try(GetInstanceInfo)) or nil
  local run = s.dungeonRun
  if run and (time() - (run.last or run.start)) > 1800 then dungeonFinish(s); run = nil end
  if inside and (kind == "party" or kind == "raid") and name then
    if run and run.name ~= name then dungeonFinish(s); run = nil end
    if not run then
      s.dungeonRun = { name = name, type = kind, start = time(), last = time(), date = date("%Y-%m-%d %H:%M"),
        level = UnitLevel("player"), xp0 = xpTotal(s), copper0 = GetMoney() or 0 }
    else
      run.last = time()
      run.outDead = nil
    end
  elseif run then
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
      -- released outside: a corpse run back in keeps the visit going; the clock stops meanwhile
      if not run.outDead then run.last = time(); run.outDead = true end
    else
      -- left the instance alive, or came back to life outside it
      if not run.outDead then run.last = time() end
      dungeonFinish(s)
    end
  end
end

---------------------------------------------------------------- travel (flights and corpse runs)
local flightStart, deadStart

local function travelRec(s)
  local t = s.travel or { flight = 0, flights = 0, ghost = 0, ghostRuns = 0, byLevel = {} }
  t.byLevel = t.byLevel or {}
  s.travel = t
  return t
end

local function travelAdd(kind, sec)
  if not sec or sec <= 0 or sec > 3600 then return end
  local s = store()
  local t = travelRec(s)
  t[kind] = (t[kind] or 0) + sec
  if kind == "flight" then t.flights = (t.flights or 0) + 1 else t.ghostRuns = (t.ghostRuns or 0) + 1 end
  local key = tostring(UnitLevel("player") or 0)
  local b = t.byLevel[key] or { flight = 0, ghost = 0 }
  b[kind] = (b[kind] or 0) + sec
  t.byLevel[key] = b
end

local function flightCheck()
  local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
  if onTaxi and not flightStart then
    flightStart = time()
  elseif not onTaxi and flightStart then
    travelAdd("flight", time() - flightStart)
    flightStart = nil
  end
end

local function ghostCheck()
  if deadStart and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
    travelAdd("ghost", time() - deadStart)
    deadStart = nil
  end
end

---------------------------------------------------------------- library books (WoW Forever)
-- Every library book is handed in with a quest of its own (same IDs for both factions),
-- so the count is simply the number of these quests the character has completed.
-- Quest IDs from Questie's Forever data (QuestieDB, foreverQuestFixes.lua).
local BOOK_QUESTS = {
  { 78124, "Nar'thalas Almanac, Vol. 74" },
  { 78127, "The Dalaran Digest, Vol. 23" },
  { 78142, "Bewitchments and Glamours" },
  { 78143, "Secrets of the Dreamers" },
  { 78145, "Arcanic Systems Manual" },
  { 78146, "Goaz Scrolls" },
  { 78147, "Crimes Against Anatomy" },
  { 78148, "Runes of the Sorcerer-Kings" },
  { 78149, "Fury of the Land" },
  { 79091, "Archmage Antonidas: The Unabridged Autobiography" },
  { 79092, "Archmage Theocritus' Research Journal" },
  { 79093, "Rumi of Gnomeregan: The Collected Works" },
  { 79094, "The Lessons of Ta'zo" },
  { 79095, "The Apothecary's Metaphysical Primer" },
  { 79096, "Ataeric: On Arcane Curiosities" },
  { 79097, "Baxtan: On Destructive Magics" },
  { 79535, "Basilisks: Should Petrification be Feared?" },
  { 79947, "Geomancy: The Stone-Cold Truth" },
  { 79948, "Defensive Magics 101" },
  { 79949, "A Web of Lies: Debunking Myths and Legends" },
  { 79950, "Demons and You" },
  { 79951, "Mummies: A Guide to the Unsavory Undead" },
  { 79952, "RwlRwlRwlRwl!" },
  { 79953, "A Ludite's Guide to Caring for Your Demonic Pet" },
  { 81947, "Sanguine Sorcery" },
  { 81949, "Legends of the Tidesages" },
  { 81951, "The Liminal and the Arcane" },
  { 81952, "Everyday Etiquette" },
  { 81953, "Stonewrought Design" },
  { 81954, "Venomous Journeys" },
  { 81955, "A Mind of Metal" },
  { 81956, "Conjurer's Codex" },
  { 84395, "Undead Potatoes" },
  { 84396, "Magma or Lava?" },
  { 84397, "Northern Kalimdor - A Comprehensive Guide" },
  { 84398, "A Study of the Light" },
  { 84399, "Ka-Boom!" },
  { 84400, "The Knight and the Lady" },
  { 84401, "Scourge: Undead Menace or Misunderstood?" },
  { 84402, "Necromancy 101" },
}
local BOOK_REWARDS = { friend = 78150, greater20 = 79536, greater25 = 82208 }
local BOOK_IDS = {}
for _, b in ipairs(BOOK_QUESTS) do BOOK_IDS[b[1]] = b[2] end

local function questDone(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return try(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false end
  if IsQuestFlaggedCompleted then return try(IsQuestFlaggedCompleted, id) and true or false end
  return false
end

local function libraryBooks()
  local done, missing = {}, {}
  for _, b in ipairs(BOOK_QUESTS) do
    local list = questDone(b[1]) and done or missing
    list[#list + 1] = { quest = b[1], title = b[2] }
  end
  local rewards = {}
  for k, id in pairs(BOOK_REWARDS) do rewards[k] = questDone(id) end
  return { count = #done, total = #BOOK_QUESTS, done = done, missing = missing, rewards = rewards }
end

---------------------------------------------------------------- deaths, gold and repairs
local function onDeath()
  local s = store()
  s.deaths = s.deaths or {}
  s.deaths[#s.deaths + 1] = { date = date("%Y-%m-%d %H:%M"), ts = time(), level = UnitLevel("player"),
    zone = GetRealZoneText and GetRealZoneText() or "", subzone = GetSubZoneText and GetSubZoneText() or "" }
  while #s.deaths > 100 do table.remove(s.deaths, 1) end
  s.deathCount = (s.deathCount or 0) + 1
  -- every death per level (the list above keeps only the latest)
  s.deathsByLevel = s.deathsByLevel or {}
  local key = tostring(UnitLevel("player") or 0)
  s.deathsByLevel[key] = (s.deathsByLevel[key] or 0) + 1
  local z = zoneRec(s, currentZone())
  if z then z.deaths = z.deaths + 1 end
  bump("deaths")
  deadStart = time()
end

local function goldDay(s)
  s.goldDays = s.goldDays or {}
  s.goldDays[date("%Y-%m-%d")] = GetMoney and GetMoney() or 0
  local keys = {}
  for k in pairs(s.goldDays) do keys[#keys + 1] = k end
  if #keys > 120 then
    table.sort(keys)
    for i = 1, #keys - 120 do s.goldDays[keys[i]] = nil end
  end
end

-- A repair shows as the repair cost dropping while a merchant is open: the drop is
-- what was paid (single-item repairs included, guild bank repairs too).
local merchantOpen, repairCost = false, nil
local function repairCheck()
  if not (merchantOpen and GetRepairAllCost) then return end
  local cost = try(GetRepairAllCost) or 0
  if repairCost and cost < repairCost then
    local s = store()
    local r = s.repairs or { total = 0, count = 0 }
    r.total, r.count = r.total + (repairCost - cost), r.count + 1
    r.last = { date = date("%Y-%m-%d %H:%M"), cost = repairCost - cost }
    s.repairs = r
  end
  repairCost = cost
end

---------------------------------------------------------------- items
local function itemName(link)
  return (try(GetItemInfo, link))
end

local function itemEquipLoc(link)
  local r = GetItemInfoInstant and { pcall(GetItemInfoInstant, link) }
  -- returns ok, itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
  if r and r[1] then return r[5], r[2] end
  return nil
end

local function itemStats(link)
  local t
  if C_Item and C_Item.GetItemStats then t = try(C_Item.GetItemStats, link) end
  if type(t) ~= "table" and GetItemStats then t = try(GetItemStats, link) end
  if type(t) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function itemLevel(link)
  return (try(GetDetailedItemLevelInfo, link))
end

local function itemRecord(link, count)
  if not link then return nil end
  local loc, id = itemEquipLoc(link)
  return {
    id = id,
    link = link,
    name = itemName(link),
    ilvl = itemLevel(link),
    equipLoc = loc,
    count = count,
    stats = itemStats(link),
  }
end

local SLOT_NAMES = {
  [1] = "head", [2] = "neck", [3] = "shoulder", [4] = "shirt", [5] = "chest", [6] = "waist",
  [7] = "legs", [8] = "feet", [9] = "wrist", [10] = "hands", [11] = "finger1", [12] = "finger2",
  [13] = "trinket1", [14] = "trinket2", [15] = "back", [16] = "mainhand", [17] = "offhand",
  [18] = "relic", [19] = "tabard",
}

local function equipped()
  local out = {}
  for slot, name in pairs(SLOT_NAMES) do
    local link = try(GetInventoryItemLink, "player", slot)
    if link then out[name] = itemRecord(link, 1) end
  end
  return out
end

---------------------------------------------------------------- containers
local function numSlots(bag)
  ---@diagnostic disable-next-line: deprecated
  local fn = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  return try(fn, bag) or 0
end

local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = try(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then return info.itemID, info.stackCount or 1, info.hyperlink end
  end
  if C_Container and C_Container.GetContainerItemID then
    local id = try(C_Container.GetContainerItemID, bag, slot)
    if id then return id, 1, C_Container.GetContainerItemLink and try(C_Container.GetContainerItemLink, bag, slot) or nil end
  end
  return nil
end

local function freeSlots(bag)
  ---@diagnostic disable-next-line: deprecated
  local fn = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
  return (try(fn, bag)) or 0
end

-- returns sizes per bag, item counts by id, and equippable gear found
local function scanBags(first, last)
  local sizes, items, gear, free = {}, {}, {}, 0
  for bag = first, last do
    local n = numSlots(bag)
    sizes[bag] = n
    free = free + freeSlots(bag)
    for slot = 1, n do
      local id, count, link = slotItem(bag, slot)
      if id then
        items[id] = (items[id] or 0) + (count or 1)
        if link then
          local loc = itemEquipLoc(link)
          if loc and loc ~= "" and loc ~= "INVTYPE_BAG" and loc ~= "INVTYPE_NON_EQUIP_IGNORE" and loc ~= "INVTYPE_AMMO" then
            gear[#gear + 1] = itemRecord(link, count)
          end
        end
      end
    end
  end
  return sizes, items, gear, free
end

---------------------------------------------------------------- professions
local function addProf(out, name, rank, max)
  if name and rank and max and max > 1 then out[name] = { rank = rank, max = max } end
end

local function professions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local r = { pcall(GetProfessions) }
    if r[1] then
      for i = 2, 7 do
        if r[i] then
          local name, _, rank, maxRank = try(GetProfessionInfo, r[i])
          addProf(out, name, rank, maxRank)
        end
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local lines = try(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if type(lines) == "table" then
      for _, id in ipairs(lines) do
        local info = try(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
        if type(info) == "table" and (info.skillLevel or 0) > 0 then
          -- the base name ("Mining"), not the expansion skill line, so it merges with GetProfessionInfo
          addProf(out, info.parentProfessionName or info.professionName, info.skillLevel, info.maxSkillLevel)
        end
      end
    end
  end
  return out
end

-- Recipes can only be read while a profession window is open.
local function scanRecipes()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
  -- someone else's profession (a link, the guild list, an NPC crafter) is not the player's
  if try(C_TradeSkillUI.IsTradeSkillLinked) or try(C_TradeSkillUI.IsTradeSkillGuild)
    or try(C_TradeSkillUI.IsNPCCrafting) or try(IsTradeSkillLinked) then return end
  local ids = try(C_TradeSkillUI.GetAllRecipeIDs)
  if type(ids) ~= "table" or #ids == 0 then return end
  local profName = "?"
  if C_TradeSkillUI.GetBaseProfessionInfo then
    local info = try(C_TradeSkillUI.GetBaseProfessionInfo)
    if type(info) == "table" and info.professionName then profName = info.professionName end
  end
  local known, unknown = {}, {}
  for _, id in ipairs(ids) do
    local info = try(C_TradeSkillUI.GetRecipeInfo, id)
    if type(info) == "table" and info.name then
      local rec = { id = id, name = info.name, difficulty = info.relativeDifficulty }
      if info.learned then known[#known + 1] = rec else unknown[#unknown + 1] = rec end
    end
  end
  local s = store()
  s.recipes = s.recipes or {}
  s.recipes[profName] = { date = date("%Y-%m-%d %H:%M"), known = known, unknown = unknown }
end

---------------------------------------------------------------- quests
local function questLog()
  local out = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
  local n = try(C_QuestLog.GetNumQuestLogEntries) or 0
  for i = 1, n do
    local info = try(C_QuestLog.GetInfo, i)
    if type(info) == "table" and info.title and not info.isHeader then
      local done = C_QuestLog.IsComplete and try(C_QuestLog.IsComplete, info.questID) or false
      local objectives = {}
      if C_QuestLog.GetQuestObjectives then
        local objs = try(C_QuestLog.GetQuestObjectives, info.questID)
        if type(objs) == "table" then
          for _, o in ipairs(objs) do
            objectives[#objectives + 1] = { text = o.text, done = o.finished and true or false, have = o.numFulfilled, need = o.numRequired }
          end
        end
      end
      out[#out + 1] = { id = info.questID, title = info.title, level = info.level,
        complete = done and true or false, objectives = objectives }
    end
  end
  return out
end

local function completedQuests()
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ids = try(C_QuestLog.GetAllCompletedQuestIDs)
    if type(ids) == "table" then return ids end
  end
  return {}
end

---------------------------------------------------------------- talents
local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local n = try(C_Spell.GetSpellName, id)
    if n then return n end
  end
  return (try(GetSpellInfo, id))
end

local function funcNames(t)
  local names = {}
  if type(t) == "table" then
    for k, v in pairs(t) do if type(v) == "function" then names[#names + 1] = k end end
    table.sort(names)
  end
  return table.concat(names, ",")
end

local function talents()
  local out = { trees = {}, list = {} }
  -- old style trees
  if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
    local tabs = try(GetNumTalentTabs) or 0
    for tab = 1, tabs do
      local tree = { talents = {}, points = 0 }
      if GetTalentTabInfo then
        -- the tree name is the first text value (older clients start with it, newer ones with an id)
        for _, v in ipairs({ try(GetTalentTabInfo, tab) }) do
          if type(v) == "string" and v ~= "" then tree.name = v; break end
        end
      end
      local n = try(GetNumTalents, tab) or 0
      for i = 1, n do
        local name, _, tier, column, rank, maxRank = try(GetTalentInfo, tab, i)
        if name and (rank or 0) > 0 then
          tree.talents[#tree.talents + 1] = { name = name, tier = tier, column = column, rank = rank, max = maxRank }
          tree.points = tree.points + rank
        end
      end
      out.trees[#out.trees + 1] = tree
    end
  end
  -- trait system
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo then
    local cfg = try(C_ClassTalents.GetActiveConfigID)
    out.configID = cfg
    local info = cfg and try(C_Traits.GetConfigInfo, cfg)
    if type(info) == "table" and type(info.treeIDs) == "table" then
      for _, treeID in ipairs(info.treeIDs) do
        local nodes = try(C_Traits.GetTreeNodes, treeID)
        if type(nodes) == "table" then
          for _, nodeID in ipairs(nodes) do
            local node = try(C_Traits.GetNodeInfo, cfg, nodeID)
            -- currentRank includes granted (free) nodes, ranksPurchased does not
            local rank = 0
            if type(node) == "table" then rank = node.currentRank or node.ranksPurchased or 0 end
            if type(node) == "table" and rank > 0 then
              local name
              local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
              local entry = entryID and try(C_Traits.GetEntryInfo, cfg, entryID)
              local def = type(entry) == "table" and entry.definitionID and try(C_Traits.GetDefinitionInfo, entry.definitionID)
              if type(def) == "table" then name = def.overrideName or spellName(def.spellID) end
              out.list[#out.list + 1] = { name = name, rank = rank, max = node.maxRanks,
                tree = treeID, node = nodeID, x = node.posX, y = node.posY }
            end
          end
        end
      end
    end
  end
  out.debug = {
    C_SpecializationInfo = funcNames(C_SpecializationInfo),
    C_ClassTalents = funcNames(C_ClassTalents),
    GetNumTalents = GetNumTalents and true or false,
  }
  if UnitCharacterPoints then out.unspent = (try(UnitCharacterPoints, "player")) end
  return out
end

---------------------------------------------------------------- reputation
-- One reputation API for both client styles: count, row(i) and expand/collapse.
-- row(i) returns a table: name, isHeader, isCollapsed, hasRep and the standing fields.
local function repAPI()
  if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    return C_Reputation.GetNumFactions, function(i)
      local f = try(C_Reputation.GetFactionDataByIndex, i)
      if type(f) ~= "table" or not f.name then return nil end
      return { name = f.name, isHeader = f.isHeader, isCollapsed = f.isCollapsed, hasRep = f.isHeaderWithRep,
        standing = f.reaction, value = f.currentStanding, min = f.currentReactionThreshold, max = f.nextReactionThreshold }
    end, C_Reputation.ExpandFactionHeader, C_Reputation.CollapseFactionHeader
  elseif GetNumFactions and GetFactionInfo then
    return GetNumFactions, function(i)
      local name, _, standing, min, max, value, _, _, isHeader, isCollapsed, hasRep = try(GetFactionInfo, i)
      if not name then return nil end
      return { name = name, isHeader = isHeader, isCollapsed = isCollapsed, hasRep = hasRep,
        standing = standing, value = value, min = min, max = max }
    end, ExpandFactionHeader, CollapseFactionHeader
  end
end

-- The game lists only the rows the player has expanded: open every header for the
-- scan and close the ones that were closed again afterwards.
local function reputation()
  local out = {}
  local numFn, row, expand, collapse = repAPI()
  if not numFn then return out end
  local reopened = {}
  if expand then
    local i, guard = 1, 0
    while i <= (try(numFn) or 0) and guard < 500 do
      guard = guard + 1
      local f = row(i)
      if f and f.isHeader and f.isCollapsed then
        reopened[f.name] = true
        try(expand, i)
      end
      i = i + 1
    end
  end
  for i = 1, try(numFn) or 0 do
    local f = row(i)
    -- headers with a standing of their own (hasRep) are factions too
    if f and (not f.isHeader or f.hasRep) then
      out[#out + 1] = { name = f.name, standing = f.standing, value = f.value, min = f.min, max = f.max }
    end
  end
  if collapse and next(reopened) then
    for i = try(numFn) or 0, 1, -1 do
      local f = row(i)
      if f and f.isHeader and reopened[f.name] and not f.isCollapsed then try(collapse, i) end
    end
  end
  return out
end

---------------------------------------------------------------- character sheet
local function sheet()
  local t = {}
  local names = { "str", "agi", "sta", "int", "spi" }
  for i, n in ipairs(names) do
    local base, total = try(UnitStat, "player", i)
    t[n] = total or base
  end
  local b, p, n = try(UnitAttackPower, "player")
  if b then t.ap = b + (p or 0) + (n or 0) end
  local _, armor = try(UnitArmor, "player")
  t.armor = armor
  t.crit = try(GetCritChance)
  t.dodge = try(GetDodgeChance)
  t.health = try(UnitHealthMax, "player")
  t.form = try(GetShapeshiftForm)
  return t
end

---------------------------------------------------------------- spells (known, for trainer reminders)
local function spells()
  local out = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
    local lines = try(C_SpellBook.GetNumSpellBookSkillLines) or 0
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    -- only learned spells: no "future" (not yet learned) entries, no flyouts, no off-spec lines
    local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for l = 1, lines do
      local li = try(C_SpellBook.GetSpellBookSkillLineInfo, l)
      if type(li) == "table" and not li.offSpecID then
        for i = (li.itemIndexOffset or 0) + 1, (li.itemIndexOffset or 0) + (li.numSpellBookItems or 0) do
          local si = try(C_SpellBook.GetSpellBookItemInfo, i, bank)
          if type(si) == "table" and si.name and not si.isPassive and not si.isOffSpec
            and (not SPELL or si.itemType == nil or si.itemType == SPELL) then
            out[#out + 1] = { id = si.spellID, name = si.name, sub = si.subName, tab = li.name }
          end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
    local tabs = try(GetNumSpellTabs) or 0
    for tab = 1, tabs do
      local tabName, _, offset, num = try(GetSpellTabInfo, tab)
      for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local name, sub, id = try(GetSpellBookItemName, i, "spell")
        local kind = GetSpellBookItemInfo and try(GetSpellBookItemInfo, i, "spell")
        if name and kind ~= "FUTURESPELL" then out[#out + 1] = { id = id, name = name, sub = sub, tab = tabName } end
      end
    end
  end
  return out
end

---------------------------------------------------------------- api info
local function apiInfo()
  local t = {}
  local function has(name, v) t[name] = v and true or false end
  has("GetNumTalentTabs", GetNumTalentTabs)
  has("GetTalentInfo", GetTalentInfo)
  has("GetTalentTabInfo", GetTalentTabInfo)
  has("C_ClassTalents", C_ClassTalents)
  has("C_Traits", C_Traits)
  has("C_SpecializationInfo", C_SpecializationInfo)
  has("C_Item.GetItemStats", C_Item and C_Item.GetItemStats)
  has("GetItemStats", GetItemStats)
  has("C_Reputation.GetFactionDataByIndex", C_Reputation and C_Reputation.GetFactionDataByIndex)
  has("GetFactionInfo", GetFactionInfo)
  has("C_SpellBook.GetSpellBookItemInfo", C_SpellBook and C_SpellBook.GetSpellBookItemInfo)
  has("GetSpellBookItemName", GetSpellBookItemName)
  has("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs)
  has("C_Bank", C_Bank)
  if GetBuildInfo then
    local v, build, _, toc = try(GetBuildInfo)
    t.build = tostring(v) .. " " .. tostring(build) .. " toc " .. tostring(toc)
  end
  return t
end

---------------------------------------------------------------- VendorFloor (optional)
-- If Bencepo's VendorFloor is installed, its ledger (account-wide) is read through
-- VendorFloor_Ledger(). Without it nothing changes.
local function vendorFloorLedger()
  if type(VendorFloor_Ledger) ~= "function" then return nil end
  local ok, l = pcall(VendorFloor_Ledger)
  if ok and type(l) == "table" then return l end
  return nil
end

local function flipProfit()
  local l = vendorFloorLedger()
  return l and tonumber(l.profit) or nil
end

---------------------------------------------------------------- sessions (xp and gold per play session)
-- The current session lives in the saved data so a /reload continues it. It ends after
-- 15 minutes without the player being online (the minute clock keeps it alive).
local SESSION_GAP = 900

-- Writes a session into the list. A closed session ends at its last activity.
local function sessionSave(cur, closed)
  if not cur or not cur.start then return end
  local s = store()
  s.sessions = s.sessions or {}
  local stop = closed and (cur.last or cur.start) or time()
  local copperNow = closed and cur.lastCopper or GetMoney() or 0
  local rec = { date = cur.date, minutes = math.floor(math.max(0, stop - cur.start) / 60),
    levelStart = cur.level, levelEnd = closed and (cur.lastLevel or cur.level) or UnitLevel("player"),
    xpGained = cur.xpGained or 0, copperDelta = copperNow - (cur.copper or copperNow),
    kills = cur.kills or 0, quests = cur.quests or 0, deaths = cur.deaths or 0, loot = cur.loot or 0 }
  local flip = closed and cur.lastFlip or flipProfit()
  if flip then
    if not cur.flip then cur.flip = flip end
    rec.flipProfit = flip - cur.flip
  end
  local list = s.sessions
  if list[#list] and list[#list].date == rec.date then list[#list] = rec else list[#list + 1] = rec end
  -- older sessions are summed up per month instead of being dropped
  while #list > 30 do
    local old = table.remove(list, 1)
    s.sessionMonths = s.sessionMonths or {}
    local m = tostring(old.date or ""):sub(1, 7)
    local agg = s.sessionMonths[m] or { sessions = 0, minutes = 0, xp = 0, copper = 0 }
    agg.sessions = agg.sessions + 1
    agg.minutes = agg.minutes + (old.minutes or 0)
    agg.xp = agg.xp + (old.xpGained or 0)
    agg.copper = agg.copper + (old.copperDelta or 0)
    s.sessionMonths[m] = agg
  end
end

local function sessionExpired(cur)
  return not cur or (time() - (cur.last or 0)) > SESSION_GAP
end

-- The running session; an expired one is saved and a new one started.
local function sessionGet()
  if not xpReady() then return nil end
  local s = store()
  local cur = s.session
  if cur and sessionExpired(cur) then
    sessionSave(cur, true)
    cur = nil
  end
  if not cur then
    local now = time()
    cur = { start = now, last = now, date = date("%Y-%m-%d %H:%M"), level = UnitLevel("player"),
      copper = GetMoney() or 0, xpGained = 0, flip = flipProfit() }
    s.session = cur
  end
  return cur
end

-- Marks activity: keeps the session from expiring and remembers where it stands.
sessionTouch = function()
  local cur = sessionGet()
  if not cur then return nil end
  cur.last = time()
  cur.lastCopper = GetMoney() or cur.lastCopper
  cur.lastLevel = UnitLevel("player") or cur.lastLevel
  cur.lastFlip = flipProfit() or cur.lastFlip
  return cur
end

-- XP gained since the last check, kept apart from the session so no gain is lost when a
-- session starts. A jump over several levels adds the full XP of the levels in between.
local function trackXP()
  if not xpReady() then return end
  local s = store()
  local xp, max, lvl = UnitXP("player") or 0, UnitXPMax("player") or 0, UnitLevel("player") or 0
  local t = s.xpTrack
  local gained = 0
  if t and t.level then
    if lvl > t.level then
      local scale = XP_TABLE[t.level] and (t.max or 0) > 0 and t.max / XP_TABLE[t.level] or 1
      local first = math.max(0, (t.max or 0) - (t.xp or 0))
      addXP(t.level, "total", first)
      gained = first
      for L = t.level + 1, lvl - 1 do
        local need = xpForLevel(L, scale) or 0
        addXP(L, "total", need)
        gained = gained + need
      end
      addXP(lvl, "total", xp)
      gained = gained + xp
    elseif lvl == t.level and xp > (t.xp or 0) then
      gained = xp - (t.xp or 0)
      addXP(lvl, "total", gained)
    elseif lvl == t.level and xp < (t.xp or 0) and not t.dropSeen then
      -- the XP event can come before the level changes: wait for the level instead of
      -- taking the small value as the new start (a second drop in a row is taken as it is)
      t.dropSeen = true
      return
    end
  end
  s.xpTrack = { xp = xp, max = max, level = lvl }
  if gained > 0 then
    local cur = sessionTouch()
    if cur then cur.xpGained = (cur.xpGained or 0) + gained end
  end
end

---------------------------------------------------------------- bank (only readable while the bank is open)
-- Bank bag IDs: the bank itself plus the bank bags after the character bags (5-10 on
-- Classic clients); the character bank tabs where the client has them.
local function bankBagIDs()
  local B = Enum and Enum.BagIndex
  if B and B.CharacterBankTab_1 then
    local ids = {}
    for i = 1, 6 do
      local id = B["CharacterBankTab_" .. i]
      if id then ids[#ids + 1] = id end
    end
    return ids
  end
  local ids = { BANK_CONTAINER or -1 }
  local first = lastBagID() + 1
  for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do ids[#ids + 1] = bag end
  return ids
end

local bankOpen = false
local function scanBank()
  -- bank contents can only be read while it is open (the scan may run a second late)
  if not bankOpen then return end
  local items, gear, sizes, total = {}, {}, {}, 0
  for _, bag in ipairs(bankBagIDs()) do
    local n = numSlots(bag)
    if n > 0 then
      sizes[#sizes + 1] = { bag = bag, slots = n }
      total = total + n
      for slot = 1, n do
        local id, count, link = slotItem(bag, slot)
        if id then
          items[id] = (items[id] or 0) + (count or 1)
          if link then
            local loc = itemEquipLoc(link)
            if loc and loc ~= "" and loc ~= "INVTYPE_BAG" and loc ~= "INVTYPE_NON_EQUIP_IGNORE" and loc ~= "INVTYPE_AMMO" then
              gear[#gear + 1] = itemRecord(link, count)
            end
          end
        end
      end
    end
  end
  if total == 0 then return end
  local s = store()
  local found = 0
  for _ in pairs(items) do found = found + 1 end
  s.bank = { date = date("%Y-%m-%d %H:%M"), sizes = sizes, items = items, gear = gear, kinds = found }
end

---------------------------------------------------------------- pace (XP per hour, time to the next level and the cap)
-- XP per online hour from the last full levels (up to 5) plus the running level.
-- Session XP per hour comes from the current play session.
local function pace(s)
  s = s or store()
  local level = UnitLevel("player") or s.level or 0
  local xp = UnitXP("player") or s.xp or 0
  local xpMax = UnitXPMax("player") or s.xpMax or 0
  local cap = maxLevel()
  local out = { level = level, maxLevel = cap }
  if level >= cap or xpMax == 0 then out.atCap = level >= cap or nil; return out end
  local scale = XP_TABLE[level] and xpMax / XP_TABLE[level] or 1
  local gained, secs, used = 0, 0, 0
  local splits = s.splits or {}
  for i = #splits, 1, -1 do
    local sp = splits[i]
    if used >= 5 then break end
    if sp.dur and sp.dur > 0 and not sp.partial then
      local need = xpForLevel(sp.level - 1, scale)
      if need then gained, secs, used = gained + need, secs + sp.dur, used + 1 end
    end
  end
  local since = s.levelSince
  if since and since.level == level and not since.partial and s.online and since.online then
    local d = s.online - since.online
    if d > 300 then gained, secs = gained + xp, secs + d end
  end
  if secs > 0 and gained > 0 then out.xpPerHour = math.floor(gained / secs * 3600 + 0.5) end
  out.levelsUsed = used
  local cur = s.session
  if cur and cur.start and (time() - (cur.last or 0)) <= 900 then
    local d = time() - cur.start
    out.sessionMinutes = math.floor(d / 60)
    if d >= 300 and (cur.xpGained or 0) > 0 then out.sessionXpPerHour = math.floor(cur.xpGained / d * 3600 + 0.5) end
  end
  local toNext = xpMax - xp
  local toCap = toNext ---@type number?
  -- without XP values for every level up to the cap there is no honest total
  for L = level + 1, cap - 1 do
    local need = xpForLevel(L, scale)
    if not need then toCap = nil; break end
    toCap = (toCap or 0) + need
  end
  out.xpToNext, out.xpToCap = toNext, toCap
  local rate = out.xpPerHour or out.sessionXpPerHour
  if rate and rate > 0 then
    out.secToNext = math.floor(toNext / rate * 3600 + 0.5)
    out.secToCap = toCap and math.floor(toCap / rate * 3600 + 0.5) or nil
    out.rateFrom = out.xpPerHour and "levels" or "session"
  end
  return out
end

local function hm(sec)
  if not sec then return "?" end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  if h > 0 then return h .. " h " .. m .. " min" end
  return m .. " min"
end

local function thousands(n)
  n = math.floor(tonumber(n) or 0)
  local sign = n < 0 and "-" or ""
  local out = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return sign .. (out:gsub("^,", ""))
end

---------------------------------------------------------------- snapshot
-- The completed quest list is long: read at login and after a quest turn-in only.
local questsDirty = true

-- Returns the character data, or nil and "not ready" while the game has not loaded the
-- character's values yet (a moment after login).
local function snapshot()
  local _, name, realm = charKey()
  if not xpReady() then return nil, "not ready" end
  local s = store()
  local lastBag = lastBagID()
  local sizes, items, gear, free = scanBags(0, lastBag)
  s.version = VERSION
  s.ts = time()
  s.date = date("%Y-%m-%d %H:%M")
  s.name, s.realm = name, realm
  s.class = select(2, try(UnitClass, "player"))
  s.race = select(2, try(UnitRace, "player"))
  s.level = UnitLevel("player")
  s.xp = UnitXP("player")
  s.xpMax = UnitXPMax("player")
  s.rested = GetXPExhaustion and GetXPExhaustion() or 0
  s.copper = GetMoney and GetMoney() or 0
  s.zone = GetRealZoneText and GetRealZoneText() or ""
  s.subzone = GetSubZoneText and GetSubZoneText() or ""
  s.hearth = try(GetBindLocation)
  s.bags = { backpack = sizes[0], sizes[1], sizes[2], sizes[3], sizes[4] }
  s.reagentBag = lastBag >= 5 and sizes[5] or nil
  s.freeSlots = free
  s.items = items
  s.bagGear = gear
  s.equipped = equipped()
  s.professions = professions()
  s.questLog = questLog()
  if questsDirty or not s.completedQuests then
    s.completedQuests = completedQuests()
    questsDirty = false
  end
  s.talents = talents()
  s.reputation = reputation()
  s.libraryBooks = libraryBooks()
  s.vendorFloor = nil -- read from VendorFloor at export time instead of copying its ledger here
  s.sheet = sheet()
  s.spells = spells()
  s.api = apiInfo()
  trackXP()
  sessionSave(sessionGet())
  clockTick()
  levelInit()
  goldDay(s)
  return s
end

-- A snapshot scans bags, gear, quests, talents, reputation and the spellbook. Frequent
-- events (looting, selling, money, XP) only mark it as stale; it is then rebuilt at most
-- once a minute by the clock ticker, and always at logout and when the export opens.
-- Level-ups and zone changes rebuild it two seconds later (one run for a burst of events).
local snapDirty, snapPending = false, false
local function scheduleSnapshot()
  snapDirty = true
end
local function flushSnapshot(force)
  if not (snapDirty or force) then return end
  snapDirty = false
  pcall(snapshot)
end
local function snapshotSoon()
  if snapPending then return end
  snapPending = true
  C_Timer.After(2, function()
    snapPending, snapDirty = false, false
    pcall(snapshot)
  end)
end

---------------------------------------------------------------- data from older versions
local function migrate()
  local s = store()
  -- XP tracking moved out of the session (1.4)
  if not s.xpTrack then
    local cur = s.session
    if cur and cur.lastLevel and cur.lastXP then
      s.xpTrack = { xp = cur.lastXP, max = cur.lastMax, level = cur.lastLevel }
    elseif s.level and s.xp then
      s.xpTrack = { xp = s.xp, max = s.xpMax, level = s.level }
    end
  end
  if s.session then s.session.lastXP, s.session.lastMax = nil, nil end
  -- deaths per level: rebuilt from the death list when it still holds every death
  if not s.deathsByLevel and s.deaths and #s.deaths >= (s.deathCount or 0) then
    s.deathsByLevel = {}
    for _, d in ipairs(s.deaths) do
      local key = tostring(d.level or 0)
      s.deathsByLevel[key] = (s.deathsByLevel[key] or 0) + 1
    end
  end
end

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
local EVENTS = { "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY",
  "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "CHARACTER_POINTS_CHANGED", "BANKFRAME_OPENED",
  "PLAYERBANKSLOTS_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "PLAYER_DEAD",
  "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM", "MERCHANT_SHOW", "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY",
  "CHAT_MSG_LOOT", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ALIVE", "PLAYER_UNGHOST",
  "GET_ITEM_INFO_RECEIVED" }
for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end

f:RegisterEvent("BANKFRAME_CLOSED")

-- Moving items in the bank and crafting fire these events many times in a row:
-- one scan a second after the first of a burst.
local soonPending = {}
local function soon(fn)
  if soonPending[fn] then return end
  soonPending[fn] = true
  C_Timer.After(1, function()
    soonPending[fn] = nil
    pcall(fn)
  end)
end
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    pcall(migrate)
    pcall(snapshot)
    clockZone = currentZone()
    C_Timer.NewTicker(60, function()
      pcall(clockTick)
      flushSnapshot()
    end)
  elseif event == "PLAYER_LOGOUT" then
    pcall(clockTick)
    pcall(flightCheck)
    -- the session as of its last activity, in case the values are gone already
    pcall(function()
      local cur = store().session
      if cur and not sessionExpired(cur) then sessionSave(cur, true) end
    end)
    flushSnapshot(true)
  elseif event == "PLAYER_LEVEL_UP" then
    pcall(onLevelUp, ...)
    pcall(trackXP)
    snapshotSoon()
  elseif event == "QUEST_TURNED_IN" then
    local questID, xpReward = ...
    pcall(addXP, UnitLevel("player"), "quest", xpReward)
    pcall(function()
      local s = store()
      s.questsByLevel = s.questsByLevel or {}
      local key = tostring(UnitLevel("player") or 0)
      s.questsByLevel[key] = (s.questsByLevel[key] or 0) + 1
      bump("quests")
    end)
    questsDirty = true
    if BOOK_IDS[questID] then
      -- the completed flag can lag behind the event a moment
      local function report()
        local ok, lb = pcall(libraryBooks)
        if ok and lb then
          print(("|cff7fbf3fLevelTrail:|r library book %d of %d handed in (%s)."):format(lb.count, lb.total, BOOK_IDS[questID]))
        end
      end
      if C_Timer and C_Timer.After then C_Timer.After(1, report) else report() end
    end
    scheduleSnapshot()
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local n = numberIn(..., KILL_PATTERN)
    if n then
      pcall(addXP, UnitLevel("player"), "kill", n)
      pcall(bump, "kills")
    end
  elseif event == "CHAT_MSG_LOOT" then
    local okV, v, id, n = pcall(lootValue, ...)
    if okV and v > 0 then pcall(bump, "loot", v)
    elseif okV and id then pcall(lootQueue, id, n) end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    pcall(lootReceived, ...)
  elseif event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
    -- the taxi flag can lag behind the control event a moment
    if C_Timer and C_Timer.After then C_Timer.After(1, function() pcall(flightCheck) end) else pcall(flightCheck) end
  elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    pcall(ghostCheck)
    pcall(dungeonCheck)
  elseif event == "CHAT_MSG_SYSTEM" then
    local n = numberIn(..., EXPLORE_PATTERN)
    if n then pcall(addXP, UnitLevel("player"), "explore", n) end
  elseif event == "PLAYER_DEAD" then
    pcall(onDeath)
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    pcall(clockTick)
    pcall(dungeonCheck)
    snapshotSoon()
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- the time before the loading screen belongs to the zone left behind
    pcall(clockTick)
    pcall(dungeonCheck)
    pcall(flightCheck)
    snapshotSoon()
  elseif event == "MERCHANT_SHOW" then
    merchantOpen = true
    repairCost = try(GetRepairAllCost)
  elseif event == "MERCHANT_CLOSED" then
    merchantOpen, repairCost = false, nil
  elseif event == "UPDATE_INVENTORY_DURABILITY" then
    pcall(repairCheck)
  elseif event == "PLAYER_XP_UPDATE" then
    pcall(trackXP)
    scheduleSnapshot()
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    pcall(scanBank)
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    if bankOpen then soon(scanBank) end
  elseif event == "TRADE_SKILL_SHOW" then
    pcall(scanRecipes)
  elseif event == "TRADE_SKILL_LIST_UPDATE" then
    soon(scanRecipes)
  else
    scheduleSnapshot()
  end
end)

---------------------------------------------------------------- text export (copy and paste into the app)
local function A(t) return setmetatable(t or {}, { __arr = true }) end

local function enc(v, out)
  local t = type(v)
  if t == "nil" then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
    elseif v == math.floor(v) then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")) end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n"
      else return string.format("\\u%04x", c:byte()) end
    end) .. '"'
  elseif t == "table" then
    local n = #v
    local mt = getmetatable(v)
    local isArr = n > 0 or (mt and mt.__arr) or false
    if isArr then for k in pairs(v) do if type(k) ~= "number" then isArr = false break end end end
    if isArr then
      out[#out + 1] = "["
      for i = 1, n do if i > 1 then out[#out + 1] = "," end enc(v[i], out) end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local first = true
      for k, val in pairs(v) do
        if not first then out[#out + 1] = "," end
        first = false
        enc(tostring(k), out) out[#out + 1] = ":" enc(val, out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

local STAT = { ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
  ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
  RESISTANCE0_NAME = "armor", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps" }
local NOTE = { ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense", ITEM_MOD_FIRE_RESISTANCE_SHORT = "Fire Resistance",
  ITEM_MOD_NATURE_RESISTANCE_SHORT = "Nature Resistance", ITEM_MOD_FROST_RESISTANCE_SHORT = "Frost Resistance",
  ITEM_MOD_SHADOW_RESISTANCE_SHORT = "Shadow Resistance", ITEM_MOD_ARCANE_RESISTANCE_SHORT = "Arcane Resistance",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mana regeneration", ITEM_MOD_SPELL_POWER_SHORT = "spell power",
  ITEM_MOD_HERBALISM_SHORT = "Herbalism", ITEM_MOD_CRIT_RATING_SHORT = "Crit", ITEM_MOD_HIT_RATING_SHORT = "Hit",
  ITEM_MOD_DODGE_RATING_SHORT = "Dodge", ITEM_MOD_HEALTH_REGENERATION_SHORT = "health regeneration" }

local function gearOut(it)
  local o = { name = it.name, ilvl = it.ilvl, wid = it.id, loc = it.equipLoc }
  local q = tostring(it.link or ""):match("|cnIQ(%d)")
  if q then o.q = tonumber(q) end
  local notes = {}
  for k, v in pairs(it.stats or {}) do
    if STAT[k] then
      o[STAT[k]] = v
    elseif NOTE[k] then
      notes[#notes + 1] = "+" .. tostring(v) .. " " .. NOTE[k]
    elseif not k:match("^RESISTANCE") then
      notes[#notes + 1] = "+" .. tostring(v) .. " " .. k:gsub("ITEM_MOD_", ""):gsub("_SHORT", ""):gsub("_", " "):lower()
    end
  end
  table.sort(notes)
  if #notes > 0 then o.note = table.concat(notes, ", ") end
  return o
end

local FORM = { [0] = "Caster", [1] = "Bear", [2] = "Aquatic", [3] = "Cat", [4] = "Travel" }

-- VendorFloor ledger for the export: totals and an array of days, oldest first.
local function vfOut(l)
  if type(l) ~= "table" then return nil end
  local days, keys = A(), {}
  for k in pairs(l.days or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local d = l.days[k]
    days[#days + 1] = { d = k, spent = d.spent, sold = d.sold, profit = math.floor((d.sold or 0) - (d.soldCost or 0)) }
  end
  return { buys = l.buys, spent = l.spent, sold = l.sold, profit = l.profit,
    unsoldUnits = l.unsoldUnits, unsoldValue = l.unsoldValue, days = days }
end

-- Same document shapes the app database uses, so the app can import the text directly.
local function buildExport(s)
  local sheets = {}
  if s.sheet and s.sheet.form ~= nil then
    local sh = { date = s.date }
    for k, v in pairs(s.sheet) do if k ~= "form" then sh[k] = v end end
    sheets[FORM[s.sheet.form] or ("Form " .. tostring(s.sheet.form))] = sh
  end
  local items = {}
  for id, c in pairs(s.items or {}) do items["i" .. id] = c end
  local bagGear = A()
  for _, g in ipairs(s.bagGear or {}) do bagGear[#bagGear + 1] = gearOut(g) end
  local equippedOut = {}
  for slot, it in pairs(s.equipped or {}) do
    if slot ~= "shirt" and slot ~= "tabard" then equippedOut[slot] = gearOut(it) end
  end
  local sessions = A()
  for _, x in ipairs(s.sessions or {}) do sessions[#sessions + 1] = x end
  local talentList = A()
  for _, t in ipairs((s.talents or {}).list or {}) do talentList[#talentList + 1] = { name = t.name, rank = t.rank, max = t.max } end
  local rep = A()
  for _, r in ipairs(s.reputation or {}) do rep[#rep + 1] = r end
  local splits = A()
  for _, x in ipairs(s.splits or {}) do splits[#splits + 1] = x end
  local deaths = A()
  local allDeaths = s.deaths or {}
  for i = math.max(1, #allDeaths - 19), #allDeaths do deaths[#deaths + 1] = allDeaths[i] end
  local goldDays = A()
  local days = {}
  for d in pairs(s.goldDays or {}) do days[#days + 1] = d end
  table.sort(days)
  for _, d in ipairs(days) do goldDays[#goldDays + 1] = { d = d, c = s.goldDays[d] } end
  local months = A()
  local mkeys = {}
  for m in pairs(s.sessionMonths or {}) do mkeys[#mkeys + 1] = m end
  table.sort(mkeys)
  for _, m in ipairs(mkeys) do
    local v = s.sessionMonths[m]
    months[#months + 1] = { month = m, sessions = v.sessions, minutes = v.minutes, xp = v.xp, copper = v.copper }
  end
  local zones = A()
  for name, z in pairs(s.zones or {}) do
    zones[#zones + 1] = { zone = name, time = z.time, xp = z.xp, deaths = z.deaths, first = z.first, last = z.last }
  end
  table.sort(zones, function(a, b) return (a.time or 0) > (b.time or 0) end)
  local zoneLevels = A()
  for name, levels in pairs(s.zoneLevels or {}) do
    for lvl, r in pairs(levels) do
      if (r.t or 0) >= 60 or (r.x or 0) > 0 then
        zoneLevels[#zoneLevels + 1] = { zone = name, level = tonumber(lvl), time = r.t, xp = r.x }
      end
    end
  end
  local dungeons = A()
  for _, d in ipairs(s.dungeons or {}) do dungeons[#dungeons + 1] = d end
  local trees = A()
  for _, t in ipairs((s.talents or {}).trees or {}) do trees[#trees + 1] = { name = t.name, points = t.points or 0 } end
  local logDone = 0
  for _, q in ipairs(s.questLog or {}) do if q.complete then logDone = logDone + 1 end end
  local questStats = { completed = #(s.completedQuests or {}), log = #(s.questLog or {}), logComplete = logDone,
    byLevel = s.questsByLevel }
  local char = { name = s.name, realm = s.realm, class = s.class, race = s.race, date = s.date, ts = s.ts,
    addonVersion = s.version, level = s.level, xp = s.xp, xpMax = s.xpMax,
    online = s.online, splits = splits, levelSince = s.levelSince, xpSources = s.xpSources,
    deaths = deaths, deathCount = s.deathCount or #allDeaths, goldDays = goldDays, repairs = s.repairs,
    sessionMonths = months, libraryBooks = s.libraryBooks, zones = zones, pace = pace(s), vendorFloor = vfOut(vendorFloorLedger()),
    deathsByLevel = s.deathsByLevel, firstLevel = s.firstLevel,
    zoneLevels = zoneLevels, dungeons = dungeons, dungeonRun = s.dungeonRun and { name = s.dungeonRun.name, date = s.dungeonRun.date } or nil,
    travel = s.travel, questStats = questStats, talentTrees = trees,
    rested = s.rested, copper = s.copper, zone = s.zone, subzone = s.subzone, hearth = s.hearth,
    bags = A({ s.bags[1] or 0, s.bags[2] or 0, s.bags[3] or 0, s.bags[4] or 0 }), backpack = s.bags.backpack,
    reagentBag = s.reagentBag, freeSlots = s.freeSlots, professions = s.professions, reputation = rep, sheets = sheets,
    sessions = sessions, items = items, bagGear = bagGear, talents = talentList, unspent = s.talents and s.talents.unspent,
    bank = s.bank and { date = s.bank.date, kinds = s.bank.kinds } or nil }
  local log = A()
  for _, q in ipairs(s.questLog or {}) do
    local objs = A()
    for _, o in ipairs(q.objectives or {}) do objs[#objs + 1] = { text = o.text, done = o.done } end
    log[#log + 1] = { id = q.id, title = q.title, level = q.level, complete = q.complete, objectives = objs }
  end
  local known, open = {}, {}
  for prof, r in pairs(s.recipes or {}) do
    known[prof] = A()
    for _, x in ipairs(r.known or {}) do known[prof][#known[prof] + 1] = x.name end
    open[prof] = A()
    -- still gives skill: optimal (0), medium (1) or easy (2); trivial is 3
    for _, x in ipairs(r.unknown or {}) do
      if x.difficulty and x.difficulty < 3 then open[prof][#open[prof] + 1] = x.name end
    end
  end
  local best, order = {}, {}
  for _, sp in ipairs(s.spells or {}) do
    -- "Rank 3", "Rang 3", "Rango 3": the number is the rank in every language
    local r = tonumber((sp.sub or ""):match("(%d+)")) or 0
    if not best[sp.name] then
      best[sp.name] = { name = sp.name, rank = r, tab = sp.tab }
      order[#order + 1] = sp.name
    elseif r > best[sp.name].rank then
      best[sp.name].rank = r
    end
  end
  local completed = A()
  for i, id in ipairs(s.completedQuests or {}) do completed[i] = id end
  local spellList = A()
  for _, n in ipairs(order) do spellList[#spellList + 1] = best[n] end
  return { levelTrail = 4, char = char,
    quests = { date = s.date, log = log, completed = completed },
    recipes = { date = s.date, known = known, inRange = open },
    spells = { date = s.date, spells = spellList },
    equipped = equippedOut }
end

---------------------------------------------------------------- report a bug
-- Addons cannot open a browser: a small window holds the issue link, selected for Ctrl+C.
local bugFrame
local function showBugReport()
  if not bugFrame then
    local win = CreateFrame("Frame", "LevelTrailBugFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bugFrame = win
    tinsert(UISpecialFrames, "LevelTrailBugFrame")
    win:SetSize(420, 112)
    win:SetPoint("CENTER", 0, 120)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.SetBackdrop then
      win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    end
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Report a bug")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local edit = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    edit:SetPoint("TOPLEFT", 20, -38)
    edit:SetPoint("RIGHT", -16, 0)
    edit:SetHeight(24)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() win:Hide() end)
    edit:SetScript("OnTextChanged", function(self, user)
      if user then self:SetText(BUG_URL) self:HighlightText() end
    end)
    edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    win.edit = edit
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -4, -8)
    hint:SetPoint("RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Copy with Ctrl+C. No GitHub account? Comment on CurseForge.")
  end
  bugFrame.edit:SetText(BUG_URL)
  bugFrame:Show()
  bugFrame.edit:SetFocus()
  bugFrame.edit:HighlightText()
end

local exportFrame
local function showExport(text, summary)
  if not exportFrame then
    local win = CreateFrame("Frame", "LevelTrailFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    exportFrame = win
    -- Esc closes the window even when the text box does not have the focus
    tinsert(UISpecialFrames, "LevelTrailFrame")
    win:SetSize(560, 360)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.SetBackdrop then
      win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    end
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.title:SetPoint("TOPLEFT", 14, -12)
    win.title:SetText(TITLE)
    win.info = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.info:SetPoint("TOPLEFT", 14, -30)
    win.info:SetPoint("RIGHT", -40, 0)
    win.info:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local bug = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    bug:SetSize(110, 22)
    bug:SetPoint("TOPRIGHT", -32, -8)
    bug:SetText("Report a bug")
    bug:SetScript("OnClick", showBugReport)
    win.info:SetPoint("RIGHT", bug, "LEFT", -8, 0)
    local scroll = CreateFrame("ScrollFrame", "LevelTrailScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(500)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function() win:Hide() end)
    -- keep the text unchanged and selected so Ctrl+C always copies everything
    edit:SetScript("OnTextChanged", function(self, user)
      if user and win.text then self:SetText(win.text) self:HighlightText() end
    end)
    edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    scroll:SetScrollChild(edit)
    win.edit = edit
  end
  exportFrame.text = text
  exportFrame.info:SetText((summary or "") .. "\nPress Ctrl+C, then paste it at bencepo.github.io/leveltrail. Esc closes.")
  exportFrame.edit:SetText(text)
  exportFrame:Show()
  exportFrame.edit:SetFocus()
  exportFrame.edit:HighlightText()
end

---------------------------------------------------------------- tracker window (/trail hud)
-- A small movable window with the running level, XP per hour and the time to the next
-- level and the cap. Whether it is shown and where it sits are kept per character; its
-- look (lines, size, background, lock, hide in combat) is kept for the account.
local hud
local HUD_LINES = {
  { key = "level", label = "Level and progress" },
  { key = "onLevel", label = "Time on this level" },
  { key = "session", label = "Play session" },
  { key = "pace", label = "Pace (XP per hour)" },
  { key = "next", label = "Time to the next level" },
  { key = "cap", label = "Time to the level cap" },
}
local HUD_DEFAULTS = { scale = 1, alpha = 0.6, locked = false, hideInCombat = false, lines = {} }

local function hudSettings()
  LevelTrailSettings = type(LevelTrailSettings) == "table" and LevelTrailSettings or {}
  local t = type(LevelTrailSettings.tracker) == "table" and LevelTrailSettings.tracker or {}
  LevelTrailSettings.tracker = t
  for k, v in pairs(HUD_DEFAULTS) do
    if t[k] == nil then t[k] = type(v) == "table" and {} or v end
  end
  return t
end

-- Every line is on unless switched off, so lines added later show up by default.
local function lineOn(key)
  return hudSettings().lines[key] ~= false
end

-- all = true for the minimap tooltip, which always shows every line.
local function hudLines(all)
  local s = store()
  local p = pace(s)
  local lines = {}
  local function add(key, text)
    if all or lineOn(key) then lines[#lines + 1] = text end
  end
  local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 0
  if p.atCap then
    add("level", ("Level %d, the cap"):format(p.level))
  else
    add("level", ("Level %d  %d%%"):format(p.level, xpMax > 0 and math.floor(xp / xpMax * 100) or 0))
  end
  local since = s.levelSince
  if since and since.level == p.level and s.online and since.online then
    add("onLevel", "On this level: " .. hm(s.online - since.online) .. (since.partial and " (since install)" or ""))
  end
  if p.sessionXpPerHour then
    add("session", "Session: " .. thousands(p.sessionXpPerHour) .. " XP/h, " .. hm((p.sessionMinutes or 0) * 60))
  elseif p.sessionMinutes then
    add("session", "Session: " .. hm(p.sessionMinutes * 60))
  end
  if p.xpPerHour then
    add("pace", "Pace: " .. thousands(p.xpPerHour) .. " XP/h (last " .. (p.levelsUsed or 0) .. " levels)")
  end
  if not p.atCap then
    if p.secToNext then
      add("next", "Next level: " .. hm(p.secToNext))
      add("cap", ("Level %d: %s online"):format(p.maxLevel, hm(p.secToCap)))
    else
      add("next", "Time to level: after the first full level")
    end
  end
  if #lines == 0 then lines[1] = "LevelTrail: no lines chosen" end
  return table.concat(lines, "\n")
end

local function hudUpdate()
  if hud and hud:IsShown() then
    local ok, text = pcall(hudLines)
    hud.text:SetText(ok and text or "LevelTrail: " .. tostring(text))
    hud:SetHeight(hud.text:GetStringHeight() + 16)
  end
end

local function hudApplyLook()
  if not hud then return end
  local t = hudSettings()
  hud:SetScale(t.scale)
  if hud.SetBackdropColor then
    hud:SetBackdropColor(0, 0, 0, t.alpha)
    hud:SetBackdropBorderColor(1, 1, 1, t.alpha > 0 and 1 or 0)
  end
  -- locked: clicks go through to the game world
  hud:EnableMouse(not t.locked)
  hudUpdate()
end

local inCombat = false
-- Shown when the character wants it and it is not hidden for combat.
local function hudRefreshShown()
  local st = store().hud
  local want = st and st.shown and not (inCombat and hudSettings().hideInCombat)
  if want then
    if not hud then return end
    hud:Show()
    hudUpdate()
  elseif hud then
    hud:Hide()
  end
end

local function hudSavePosition()
  local point, _, rel, x, y = hud:GetPoint()
  local st = store()
  st.hud = st.hud or {}
  st.hud.point, st.hud.rel, st.hud.x, st.hud.y = point, rel, x, y
end

local function hudCreate()
  if hud then return hud end
  local win = CreateFrame("Frame", "LevelTrailTracker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(230, 80)
  win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -200)
  win:SetFrameStrata("MEDIUM")
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    hud = self
    hudSavePosition()
  end)
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    win:SetBackdropColor(0, 0, 0, 0.6)
  end
  win.text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.text:SetPoint("TOPLEFT", 8, -8)
  win.text:SetPoint("RIGHT", -8, 0)
  win.text:SetJustifyH("LEFT")
  local st = store().hud
  if st and st.point then
    win:ClearAllPoints()
    win:SetPoint(st.point, UIParent, st.rel or st.point, st.x or 0, st.y or 0)
  end
  local acc = 0
  win:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= 2 then acc = 0; hudUpdate() end
  end)
  hud = win
  hudApplyLook()
  return win
end

local function hudShow(show)
  local st = store()
  st.hud = st.hud or {}
  st.hud.shown = show and true or false
  if show then hudCreate() end
  hudRefreshShown()
end

local function hudResetPosition()
  local st = store()
  st.hud = st.hud or {}
  st.hud.point, st.hud.rel, st.hud.x, st.hud.y = nil, nil, nil, nil
  if hud then
    hud:ClearAllPoints()
    hud:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -200)
  end
end

---------------------------------------------------------------- tracker options window (/trail options)
-- Its own window, dragged anywhere and left open while playing, so every change shows at once.
local optionsWin
local function showOptions()
  if optionsWin then optionsWin:Toggle(); return end
  local UI = LibStub and LibStub("BencepoUI-1.0", true)
  if not UI then
    print("|cffff5555LevelTrail:|r the options window did not load. /trail hud still turns the tracker on and off.")
    return
  end
  local t = hudSettings()
  local db = LevelTrailSettings
  local win = UI:CreateWindow({ name = "LevelTrailOptions", title = "LevelTrail tracker",
    width = 440, height = 290, accent = { 0.498, 0.749, 0.247, 1 }, db = db, posKey = "optPos",
    bugUrl = BUG_URL })
  local L, R = 16, 236
  win:Header(L, -48, "Window")
  win:Check(L, -72, "Show tracker", "The small window with level, pace and time to the next level. Saved per character.",
    function() local st = store().hud; return st and st.shown end, function(v) hudShow(v) end)
  win:Check(L, -96, "Lock position", "The tracker cannot be dragged, and clicks go through it to the game.",
    function() return t.locked end, function(v) t.locked = v; hudApplyLook() end)
  win:Check(L, -120, "Hide in combat", "Hides the tracker while you are in combat.",
    function() return t.hideInCombat end, function(v) t.hideInCombat = v; hudRefreshShown() end)
  win:Slider(L, -154, "Size", 50, 200, 10, function() return math.floor(t.scale * 100 + 0.5) end,
    function(v) t.scale = v / 100; hudApplyLook() end, "Scale of the tracker.", 150, function(v) return v .. "%" end)
  win:Slider(L, -200, "Background", 0, 100, 10, function() return math.floor(t.alpha * 100 + 0.5) end,
    function(v) t.alpha = v / 100; hudApplyLook() end, "Opacity of the background. 0% shows only the text.", 150,
    function(v) return v .. "%" end)
  local reset = win:Button("Reset position", 130, function() hudResetPosition() end,
    "Puts the tracker back to its starting place at the top right.")
  reset:SetPoint("TOPLEFT", L, -252)
  win:Header(R, -48, "Lines")
  for i, line in ipairs(HUD_LINES) do
    win:Check(R, -48 - i * 24, line.label, "Show this line in the tracker.",
      function() return lineOn(line.key) end, function(v) t.lines[line.key] = v; hudUpdate() end)
  end
  optionsWin = win
  win:Show()
end

local hudEvents = CreateFrame("Frame")
hudEvents:RegisterEvent("PLAYER_LOGIN")
hudEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
hudEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
hudEvents:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local st = store().hud
    if st and st.shown then pcall(hudShow, true) end
  else
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if hudSettings().hideInCombat then pcall(hudRefreshShown) end
  end
end)

---------------------------------------------------------------- minimap button
-- Minimap icon through LibDataBroker and LibDBIcon (shipped in Libs), so minimap button
-- managers can collect it.
local function MinimapIcon(name, icon, db, onClick, onTooltip)
  local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
  local dbi = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (ldb and dbi) then return nil end
  if db.minimapPos == nil and db.angle then db.minimapPos = db.angle % 360 end
  local obj = ldb:GetDataObjectByName(name) or ldb:NewDataObject(name, {
    type = "launcher", label = name, icon = icon,
    OnClick = function(_, button) onClick(button) end,
    OnTooltipShow = function(tip) onTooltip(tip) end,
  })
  if not dbi:IsRegistered(name) then dbi:Register(name, obj, db) end
  return { SetShown = function(_, show) if show then dbi:Show(name) else dbi:Hide(name) end end }
end

local minimapButton

local function minimapClick(button)
  if IsShiftKeyDown and IsShiftKeyDown() then
    showOptions()
  elseif button == "RightButton" then
    local okH, errH = pcall(hudShow, not (hud and hud:IsShown()))
    if not okH then print("|cffff5555LevelTrail: tracker failed:|r " .. tostring(errH)) end
  else
    SlashCmdList["LEVELTRAIL"]("")
  end
end

local function minimapTooltip(tip)
  tip:AddLine(TITLE)
  local ok, text = pcall(hudLines, true)
  if ok and text then
    for line in text:gmatch("[^\n]+") do tip:AddLine(line, 1, 1, 1) end
  end
  tip:AddLine(" ")
  tip:AddLine("Left-click: export for bencepo.github.io/leveltrail", 0.6, 0.8, 1)
  tip:AddLine("Right-click: tracker window on/off", 0.6, 0.8, 1)
  tip:AddLine("Shift-click: tracker options", 0.6, 0.8, 1)
  tip:AddLine("Drag: move. /trail minimap: hide or show", 0.6, 0.8, 1)
end

-- Account-wide settings live in their own saved variable, apart from the characters
-- in LevelTrailDB (which only holds "Name-Realm" entries).
local function minimapSettings()
  LevelTrailSettings = type(LevelTrailSettings) == "table" and LevelTrailSettings or {}
  if type(LevelTrailDB._minimap) == "table" then
    LevelTrailSettings.minimap = LevelTrailSettings.minimap or LevelTrailDB._minimap
    LevelTrailDB._minimap = nil
  end
  LevelTrailSettings.minimap = LevelTrailSettings.minimap or {}
  return LevelTrailSettings.minimap
end

local minimapEvents = CreateFrame("Frame")
minimapEvents:RegisterEvent("PLAYER_LOGIN")
minimapEvents:SetScript("OnEvent", function()
  local ok, b = pcall(MinimapIcon, "LevelTrail", "Interface\\AddOns\\LevelTrail\\Icons\\minimap",
    minimapSettings(), minimapClick, minimapTooltip)
  if ok then minimapButton = b else print("|cffff5555LevelTrail: minimap button failed:|r " .. tostring(b)) end
end)

-- Entry in the game's addon menu (the compartment next to the minimap), if the client has one.
-- Depending on the client the second argument is the button name or a table with it.
function LevelTrail_OnCompartmentClick(_, input)
  local button = type(input) == "table" and input.buttonName or input
  minimapClick(button)
end

---------------------------------------------------------------- slash command
local function count(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

SLASH_LEVELTRAIL1 = "/trail"
SLASH_LEVELTRAIL2 = "/lt"
SlashCmdList["LEVELTRAIL"] = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "hud" then
    local on = not (hud and hud:IsShown())
    local okH, errH = pcall(hudShow, on)
    if not okH then print("|cffff5555LevelTrail: tracker failed:|r " .. tostring(errH)) end
    return
  elseif msg == "options" or msg == "config" then
    local okO, errO = pcall(showOptions)
    if not okO then print("|cffff5555LevelTrail: options failed:|r " .. tostring(errO)) end
    return
  elseif msg == "minimap" then
    if not minimapButton then
      print("|cffff5555LevelTrail:|r there is no minimap button (LibDBIcon did not load). Use /trail or the addon menu.")
      return
    end
    local st = minimapSettings()
    st.hide = not st.hide
    minimapButton:SetShown(not st.hide)
    print("|cff7fbf3f" .. TITLE .. "|r minimap button " .. (st.hide and "hidden" or "shown"))
    return
  elseif msg == "bug" then
    showBugReport()
    return
  elseif msg == "session" then
    local cur = store().session
    if not cur or not cur.start then print("|cff7fbf3fLevelTrail:|r no session yet."); return end
    if sessionExpired(cur) then
      print(("|cff7fbf3fLevelTrail:|r no running session. The last one started %s and lasted %s."):format(
        tostring(cur.date), hm((cur.last or cur.start) - cur.start)))
      return
    end
    print(("|cff7fbf3fLevelTrail session|r %s: %s, %s XP, %d kills, %d quests, %d deaths, loot worth %s"):format(
      hm(time() - cur.start), cur.level == UnitLevel("player") and ("level " .. cur.level) or (cur.level .. " -> " .. UnitLevel("player")),
      thousands(cur.xpGained), cur.kills or 0, cur.quests or 0, cur.deaths or 0,
      GetCoinTextureString and GetCoinTextureString(cur.loot or 0) or tostring(cur.loot or 0)))
    return
  elseif msg == "help" then
    print("|cff7fbf3f" .. TITLE .. "|r /trail: export window, /trail chat: summary in chat, /trail session: this session so far, /trail hud: tracker window on/off, /trail options: tracker options, /trail minimap: minimap button on/off, /trail bug: report a bug")
    return
  end
  -- export and chat summary: refresh the parts that only load with their window open, then everything
  pcall(scanRecipes)
  local ok, s, why = pcall(snapshot)
  if ok and not s and why == "not ready" then
    print("|cff7fbf3fLevelTrail:|r the game has not loaded your character yet. Try again in a moment.")
    return
  end
  if not ok or not s then print("|cffff5555LevelTrail: snapshot failed:|r " .. tostring(s)) return end
  local g = math.floor(s.copper / 10000)
  local sv = math.floor((s.copper % 10000) / 100)
  local tal = #s.talents.list
  local lb = s.libraryBooks
  local summary = "Level " .. tostring(s.level) .. ", " .. g .. "g " .. sv .. "s, " .. tostring(s.zone) ..
    (lb and (", library books " .. lb.count .. "/" .. lb.total) or "") .. " | " ..
    count(s.equipped) .. " items, " .. tal .. " talents, " .. #s.questLog .. " quests, " .. count(s.recipes) .. " professions with recipes"
  local okP, p = pcall(pace, s)
  if okP and p and p.secToNext then
    summary = summary .. " | " .. thousands(p.xpPerHour or p.sessionXpPerHour) .. " XP/h, next level in " ..
      hm(p.secToNext) .. ", level " .. p.maxLevel .. " in " .. hm(p.secToCap)
  end
  if msg == "chat" then
    print("|cff7fbf3f" .. TITLE .. "|r " .. summary)
    return
  end
  local okE, data = pcall(buildExport, s)
  if not okE then print("|cffff5555LevelTrail: export failed:|r " .. tostring(data)) return end
  local out = {}
  local okJ, err = pcall(enc, data, out)
  if not okJ then print("|cffff5555LevelTrail: encoding failed:|r " .. tostring(err)) return end
  local okS, err2 = pcall(showExport, table.concat(out), summary)
  if not okS then
    print("|cffff5555LevelTrail: window failed:|r " .. tostring(err2))
    print("|cff7fbf3f" .. TITLE .. "|r " .. summary .. " (type /reload to write the file instead)")
  end
end

-- For the automated tests (tests/*_spec.lua, run with busted outside the game); unused in the game.
ns.test = {
  toPattern = toPattern, numberIn = numberIn, lootValue = lootValue, xpForLevel = xpForLevel,
  pace = pace, hm = hm, thousands = thousands, trackXP = trackXP, sessionGet = sessionGet,
  sessionSave = sessionSave, bump = bump, onDeath = onDeath, buildExport = buildExport, enc = enc,
  migrate = migrate, bankBagIDs = bankBagIDs, store = store, lootQueue = lootQueue, lootReceived = lootReceived,
}
