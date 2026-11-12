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
local VERSION = 8 -- data version
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local ADDON_VERSION = GetMetadata and GetMetadata(ADDON, "Version") or ""
if ADDON_VERSION == "" or ADDON_VERSION:find("^@") then ADDON_VERSION = "dev" end
local TITLE = "LevelTrail " .. ADDON_VERSION

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h end
  return nil
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

-- Data from the addon's former name (BencepoExport) is taken over once, as long as
-- LevelTrail has none of its own yet. The old folder only has to stay installed
-- for one login.
local function migrate()
  if type(BencepoExportDB) ~= "table" or next(LevelTrailDB) ~= nil then return end
  local n = 0
  for key, data in pairs(BencepoExportDB) do
    if type(data) == "table" then LevelTrailDB[key] = data; n = n + 1 end
  end
  if n > 0 then print("|cff7fbf3fLevelTrail:|r took over the data of " .. n .. " character(s) from BencepoExport.") end
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
      if s.dungeonRun then s.dungeonRun.last = now end
    end
  end
  clockLast = now
  clockZone = currentZone()
end

local function levelInit()
  local s = store()
  local L = UnitLevel("player") or 0
  if L == 0 then return end
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
  local p = fmt:gsub("%%%d+%$", "%%")
  p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.-)")
  p = p:gsub("%%d", "(%%d+)")
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
  for _, rec in ipairs({ s.session, s.dungeonRun }) do
    if rec then rec[field] = (rec[field] or 0) + n end
  end
end

-- Vendor value of looted items, from the game's own loot lines.
local LOOT_MULTI = toPattern(LOOT_ITEM_SELF_MULTIPLE)
local LOOT_SINGLE = toPattern(LOOT_ITEM_SELF)
local function lootValue(msg)
  if type(msg) ~= "string" then return 0 end
  local link, count
  if LOOT_MULTI then link, count = msg:match(LOOT_MULTI) end
  if not link and LOOT_SINGLE then link = msg:match(LOOT_SINGLE) end
  if not link then return 0 end
  if not GetItemInfo then return 0 end
  -- try() returns at most 8 values; the sell price is the 11th
  local r = { pcall(GetItemInfo, link) }
  if not r[1] then return 0 end
  return (tonumber(r[12]) or 0) * (tonumber(count) or 1)
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
    end
  elseif run and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
    -- left the instance alive; a corpse run back in keeps the visit going
    run.last = time()
    dungeonFinish(s)
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
  if C_Item and C_Item.GetItemInfo then
    local n = try(C_Item.GetItemInfo, link)
    if n then return n end
  end
  return (try(GetItemInfo, link))
end

local function itemEquipLoc(link)
  local r
  if C_Item and C_Item.GetItemInfoInstant then
    r = { pcall(C_Item.GetItemInfoInstant, link) }
  elseif GetItemInfoInstant then
    r = { pcall(GetItemInfoInstant, link) }
  end
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
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    local l = try(C_Item.GetDetailedItemLevelInfo, link)
    if l then return l end
  end
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
  if C_Container and C_Container.GetContainerNumSlots then
    return try(C_Container.GetContainerNumSlots, bag) or 0
  end
  return try(GetContainerNumSlots, bag) or 0
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
  if C_Container and C_Container.GetContainerNumFreeSlots then
    return try(C_Container.GetContainerNumFreeSlots, bag) or 0
  end
  return try(GetContainerNumFreeSlots, bag) or 0
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
          addProf(out, info.professionName or info.parentProfessionName, info.skillLevel, info.maxSkillLevel)
        end
      end
    end
  end
  return out
end

-- Recipes can only be read while a profession window is open.
local function scanRecipes()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
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
      local rec = { id = id, name = info.name, difficulty = info.relativeDifficulty, craftable = info.numAvailable }
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
            if type(node) == "table" and (node.ranksPurchased or 0) > 0 then
              local name
              local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
              local entry = entryID and try(C_Traits.GetEntryInfo, cfg, entryID)
              local def = type(entry) == "table" and entry.definitionID and try(C_Traits.GetDefinitionInfo, entry.definitionID)
              if type(def) == "table" then name = def.overrideName or spellName(def.spellID) end
              out.list[#out.list + 1] = { name = name, rank = node.ranksPurchased, max = node.maxRanks,
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
local function reputation()
  local out = {}
  if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    local n = try(C_Reputation.GetNumFactions) or 0
    for i = 1, n do
      local f = try(C_Reputation.GetFactionDataByIndex, i)
      if type(f) == "table" and f.name and not f.isHeader then
        out[#out + 1] = { name = f.name, standing = f.reaction, value = f.currentStanding,
          min = f.currentReactionThreshold, max = f.nextReactionThreshold }
      end
    end
  elseif GetNumFactions and GetFactionInfo then
    local n = try(GetNumFactions) or 0
    for i = 1, n do
      local name, _, standing, min, max, value, _, _, isHeader = try(GetFactionInfo, i)
      if name and not isHeader then
        out[#out + 1] = { name = name, standing = standing, value = value, min = min, max = max }
      end
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
    for l = 1, lines do
      local li = try(C_SpellBook.GetSpellBookSkillLineInfo, l)
      if type(li) == "table" then
        for i = (li.itemIndexOffset or 0) + 1, (li.itemIndexOffset or 0) + (li.numSpellBookItems or 0) do
          local si = try(C_SpellBook.GetSpellBookItemInfo, i, bank)
          if type(si) == "table" and si.name and not si.isPassive then
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
        if name then out[#out + 1] = { id = id, name = name, sub = sub, tab = tabName } end
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
-- The current session lives in the saved data so a /reload continues it.
local function sessionGet()
  local s = store()
  local xpMax = UnitXPMax("player") or 0
  if xpMax == 0 then return nil end            -- values not loaded yet (login/logout)
  local cur = s.session
  if not cur or (time() - (cur.last or 0)) > 900 then
    cur = { start = time(), date = date("%Y-%m-%d %H:%M"), level = UnitLevel("player"),
      copper = GetMoney() or 0, xpGained = 0, lastXP = UnitXP("player") or 0, lastMax = xpMax, lastLevel = UnitLevel("player"),
      flip = flipProfit() }
    s.session = cur
  end
  return cur
end

local function sessionTrackXP()
  local cur = sessionGet()
  if not cur then return end
  local xp, max, lvl = UnitXP("player") or 0, UnitXPMax("player") or 0, UnitLevel("player") or 0
  if lvl > (cur.lastLevel or lvl) then
    cur.xpGained = cur.xpGained + (cur.lastMax - cur.lastXP) + xp
    addXP(cur.lastLevel, "total", cur.lastMax - cur.lastXP)
    addXP(lvl, "total", xp)
  elseif xp > cur.lastXP then
    cur.xpGained = cur.xpGained + (xp - cur.lastXP)
    addXP(lvl, "total", xp - cur.lastXP)
  end
  cur.lastXP, cur.lastMax, cur.lastLevel, cur.last = xp, max, lvl, time()
end

local function sessionSave()
  local cur = sessionGet()
  if not cur then return end
  local s = store()
  s.sessions = s.sessions or {}
  local rec = { date = cur.date, minutes = math.floor((time() - cur.start) / 60),
    levelStart = cur.level, levelEnd = UnitLevel("player"),
    xpGained = cur.xpGained, copperDelta = (GetMoney() or 0) - cur.copper,
    kills = cur.kills or 0, quests = cur.quests or 0, deaths = cur.deaths or 0, loot = cur.loot or 0 }
  local flip = flipProfit()
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

---------------------------------------------------------------- bank (only readable while the bank is open)
local function scanBank()
  local items, gear, sizes, total = {}, {}, {}, 0
  local ids = { -1 }
  -- bank bags follow the character bags; ids differ between clients, so probe a range
  for bag = 5, 13 do ids[#ids + 1] = bag end
  for _, bag in ipairs(ids) do
    if bag == -1 or bag > 5 then
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
  end
  if total == 0 then return end
  local s = store()
  local found = 0
  for _ in pairs(items) do found = found + 1 end
  s.bank = { date = date("%Y-%m-%d %H:%M"), sizes = sizes, items = items, gear = gear, kinds = found,
    debug = { C_Bank = funcNames(C_Bank) } }
end

---------------------------------------------------------------- pace (XP per hour, time to the next level and the cap)
-- XP needed for each level up to 60 (Classic table). If the game reports a different
-- value for the current level, the remaining levels are scaled by the same factor.
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
  local toCap = toNext
  for L = level + 1, cap - 1 do toCap = toCap + (xpForLevel(L, scale) or 0) end
  out.xpToNext, out.xpToCap = toNext, toCap
  local rate = out.xpPerHour or out.sessionXpPerHour
  if rate and rate > 0 then
    out.secToNext = math.floor(toNext / rate * 3600 + 0.5)
    out.secToCap = math.floor(toCap / rate * 3600 + 0.5)
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
  local str = tostring(math.floor(n or 0))
  local out = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

---------------------------------------------------------------- snapshot
local function snapshot()
  local _, name, realm = charKey()
  if (UnitXPMax("player") or 0) == 0 and (UnitLevel("player") or 0) < 60 then return nil end  -- not loaded yet
  local s = store()
  local sizes, items, gear, free = scanBags(0, 5)
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
  s.reagentBag = sizes[5]
  s.freeSlots = free
  s.items = items
  s.bagGear = gear
  s.equipped = equipped()
  s.professions = professions()
  s.questLog = questLog()
  s.completedQuests = completedQuests()
  s.talents = talents()
  s.reputation = reputation()
  s.libraryBooks = libraryBooks()
  s.vendorFloor = vendorFloorLedger()
  s.sheet = sheet()
  s.spells = spells()
  s.api = apiInfo()
  sessionTrackXP()
  sessionSave()
  clockTick()
  levelInit()
  goldDay(s)
  return s
end

-- Many events can fire at once (looting, selling): one snapshot two seconds after the last.
local snapPending = false
local function scheduleSnapshot()
  if snapPending then return end
  snapPending = true
  local function run() snapPending = false; pcall(snapshot) end
  if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
end

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
local EVENTS = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY",
  "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "CHARACTER_POINTS_CHANGED", "BANKFRAME_OPENED",
  "PLAYERBANKSLOTS_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "PLAYER_DEAD",
  "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM", "MERCHANT_SHOW", "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY",
  "CHAT_MSG_LOOT", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end

local bankOpen = false
f:RegisterEvent("BANKFRAME_CLOSED")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == ADDON then pcall(migrate) end
  elseif event == "PLAYER_LOGIN" then
    pcall(snapshot)
    clockZone = currentZone()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() pcall(clockTick) end) end
  elseif event == "PLAYER_LOGOUT" then
    pcall(clockTick)
    pcall(flightCheck)
  elseif event == "PLAYER_LEVEL_UP" then
    pcall(onLevelUp, ...)
    scheduleSnapshot()
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
    local okV, v = pcall(lootValue, ...)
    if okV and v > 0 then pcall(bump, "loot", v) end
  elseif event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
    -- the taxi flag can lag behind the control event a moment
    if C_Timer and C_Timer.After then C_Timer.After(1, function() pcall(flightCheck) end) else pcall(flightCheck) end
  elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    pcall(ghostCheck)
  elseif event == "CHAT_MSG_SYSTEM" then
    local n = numberIn(..., EXPLORE_PATTERN)
    if n then pcall(addXP, UnitLevel("player"), "explore", n) end
  elseif event == "PLAYER_DEAD" then
    pcall(onDeath)
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    pcall(clockTick)
    pcall(dungeonCheck)
    scheduleSnapshot()
  elseif event == "PLAYER_ENTERING_WORLD" then
    pcall(dungeonCheck)
    pcall(flightCheck)
    scheduleSnapshot()
  elseif event == "MERCHANT_SHOW" then
    merchantOpen = true
    repairCost = try(GetRepairAllCost)
  elseif event == "MERCHANT_CLOSED" then
    merchantOpen, repairCost = false, nil
  elseif event == "UPDATE_INVENTORY_DURABILITY" then
    pcall(repairCheck)
  elseif event == "PLAYER_XP_UPDATE" then
    pcall(sessionTrackXP)
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    pcall(scanBank)
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    if bankOpen then pcall(scanBank) end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
    pcall(scanRecipes)
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
    sessionMonths = months, libraryBooks = s.libraryBooks, zones = zones, pace = pace(s), vendorFloor = vfOut(s.vendorFloor),
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
    for _, x in ipairs(r.unknown or {}) do
      if (x.difficulty or 0) > 0 then open[prof][#open[prof] + 1] = x.name end
    end
  end
  local best, order = {}, {}
  for _, sp in ipairs(s.spells or {}) do
    local r = tonumber((sp.sub or ""):match("Rank (%d+)")) or 0
    if not best[sp.name] then
      best[sp.name] = { name = sp.name, rank = r, tab = sp.tab }
      order[#order + 1] = sp.name
    elseif r > best[sp.name].rank then
      best[sp.name].rank = r
    end
  end
  local spellList = A()
  for _, n in ipairs(order) do spellList[#spellList + 1] = best[n] end
  return { levelTrail = 4, bencepoExport = 1, char = char,
    quests = { date = s.date, log = log, completed = A(s.completedQuests) },
    recipes = { date = s.date, known = known, inRange = open },
    spells = { date = s.date, spells = spellList },
    equipped = equippedOut }
end

local exportFrame
local function showExport(text, summary)
  if not exportFrame then
    local win = CreateFrame("Frame", "LevelTrailFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
    exportFrame = win
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
-- level and the cap. Whether it is shown is kept per character.
local hud
local function hudLines()
  local s = store()
  local p = pace(s)
  local lines = {}
  local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 0
  if p.atCap then
    lines[1] = ("Level %d, the cap"):format(p.level)
  else
    lines[1] = ("Level %d  %d%%"):format(p.level, xpMax > 0 and math.floor(xp / xpMax * 100) or 0)
  end
  local since = s.levelSince
  if since and since.level == p.level and s.online and since.online then
    lines[#lines + 1] = "On this level: " .. hm(s.online - since.online) .. (since.partial and " (since install)" or "")
  end
  if p.sessionXpPerHour then
    lines[#lines + 1] = "Session: " .. thousands(p.sessionXpPerHour) .. " XP/h, " .. hm((p.sessionMinutes or 0) * 60)
  elseif p.sessionMinutes then
    lines[#lines + 1] = "Session: " .. hm(p.sessionMinutes * 60)
  end
  if p.xpPerHour then
    lines[#lines + 1] = "Pace: " .. thousands(p.xpPerHour) .. " XP/h (last " .. (p.levelsUsed or 0) .. " levels)"
  end
  if not p.atCap then
    if p.secToNext then
      lines[#lines + 1] = "Next level: " .. hm(p.secToNext)
      lines[#lines + 1] = ("Level %d: %s online"):format(p.maxLevel, hm(p.secToCap))
    else
      lines[#lines + 1] = "Time to level: after the first full level"
    end
  end
  return table.concat(lines, "\n")
end

local function hudUpdate()
  if hud and hud:IsShown() then
    local ok, text = pcall(hudLines)
    hud.text:SetText(ok and text or "LevelTrail: " .. tostring(text))
    hud:SetHeight(hud.text:GetStringHeight() + 16)
  end
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
    local point, _, rel, x, y = self:GetPoint()
    local st = store()
    st.hud = st.hud or {}
    st.hud.point, st.hud.rel, st.hud.x, st.hud.y = point, rel, x, y
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
  return win
end

local function hudShow(show)
  local st = store()
  st.hud = st.hud or {}
  st.hud.shown = show and true or false
  if show then
    hudCreate():Show()
    hudUpdate()
  elseif hud then
    hud:Hide()
  end
end

local hudEvents = CreateFrame("Frame")
hudEvents:RegisterEvent("PLAYER_LOGIN")
hudEvents:SetScript("OnEvent", function()
  local st = store().hud
  if st and st.shown then pcall(hudShow, true) end
end)

---------------------------------------------------------------- minimap button
-- A round button at the edge of the minimap. Drag it to move it; the angle is kept in
-- the saved table db (db.angle, db.hide). No libraries needed.
local function MinimapButton(name, icon, db, onClick, onTooltip)
  if not Minimap then return nil end
  local b = CreateFrame("Button", name, Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local art = b:CreateTexture(nil, "ARTWORK")
  art:SetSize(17, 17)
  art:SetTexture(icon)
  art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  art:SetPoint("TOPLEFT", 7, -6)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")
  local function place()
    local a = math.rad(db.angle or 225)
    local r = (Minimap:GetWidth() / 2) + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      db.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, button) onClick(button) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    onTooltip(GameTooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
  end)
  place()
  b:SetShown(not db.hide)
  return b
end

-- Minimap icon through LibDataBroker and LibDBIcon (shipped in Libs), so minimap button
-- managers can collect it. The own button above is only used if the libraries are missing.
local function MinimapIcon(name, icon, db, onClick, onTooltip)
  local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
  local dbi = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (ldb and dbi) then return MinimapButton(name .. "MinimapButton", icon, db, onClick, onTooltip) end
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
  if button == "RightButton" then
    local okH, errH = pcall(hudShow, not (hud and hud:IsShown()))
    if not okH then print("|cffff5555LevelTrail: tracker failed:|r " .. tostring(errH)) end
  else
    SlashCmdList["LEVELTRAIL"]("")
  end
end

local function minimapTooltip(tip)
  tip:AddLine(TITLE)
  local ok, text = pcall(hudLines)
  if ok and text then
    for line in text:gmatch("[^\n]+") do tip:AddLine(line, 1, 1, 1) end
  end
  tip:AddLine(" ")
  tip:AddLine("Left-click: export for bencepo.github.io/leveltrail", 0.6, 0.8, 1)
  tip:AddLine("Right-click: tracker window on/off", 0.6, 0.8, 1)
  tip:AddLine("Drag: move. /trail minimap: hide or show", 0.6, 0.8, 1)
end

local function minimapSettings()
  LevelTrailDB._minimap = LevelTrailDB._minimap or {}
  return LevelTrailDB._minimap
end

local minimapEvents = CreateFrame("Frame")
minimapEvents:RegisterEvent("PLAYER_LOGIN")
minimapEvents:SetScript("OnEvent", function()
  local ok, b = pcall(MinimapIcon, "LevelTrail", "Interface\\Icons\\INV_Misc_Map_01",
    minimapSettings(), minimapClick, minimapTooltip)
  if ok then minimapButton = b else print("|cffff5555LevelTrail: minimap button failed:|r " .. tostring(b)) end
end)

-- Entry in the game's addon menu (the compartment next to the minimap), if the client has one.
function LevelTrail_OnCompartmentClick(_, button)
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
SLASH_LEVELTRAIL3 = "/bx"
SlashCmdList["LEVELTRAIL"] = function(msg)
  -- refresh the parts that only load with their window open
  pcall(scanRecipes)
  local ok, s = pcall(snapshot)
  if not ok or not s then print("|cffff5555LevelTrail: snapshot failed:|r " .. tostring(s)) return end
  local g = math.floor(s.copper / 10000)
  local sv = math.floor((s.copper % 10000) / 100)
  local tal = #s.talents.list
  local lb = s.libraryBooks
  local summary = "Level " .. tostring(s.level) .. ", " .. g .. "g " .. sv .. "s, " .. tostring(s.zone) ..
    (lb and (", library books " .. lb.count .. "/" .. lb.total) or "") .. " | " ..
    count(s.equipped) .. " items, " .. tal .. " talents, " .. #s.questLog .. " quests, " .. count(s.recipes) .. " professions with recipes"
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "hud" then
    local on = not (hud and hud:IsShown())
    local okH, errH = pcall(hudShow, on)
    if not okH then print("|cffff5555LevelTrail: tracker failed:|r " .. tostring(errH)) end
    return
  elseif msg == "minimap" then
    local st = minimapSettings()
    st.hide = not st.hide
    if minimapButton then minimapButton:SetShown(not st.hide) end
    print("|cff7fbf3f" .. TITLE .. "|r minimap button " .. (st.hide and "hidden" or "shown"))
    return
  elseif msg == "session" then
    local cur = store().session
    if not cur or not cur.start then print("|cff7fbf3fLevelTrail:|r no session yet."); return end
    print(("|cff7fbf3fLevelTrail session|r %s: %s, %s XP, %d kills, %d quests, %d deaths, loot worth %s"):format(
      hm(time() - cur.start), cur.level == UnitLevel("player") and ("level " .. cur.level) or (cur.level .. " -> " .. UnitLevel("player")),
      thousands(cur.xpGained), cur.kills or 0, cur.quests or 0, cur.deaths or 0,
      GetCoinTextureString and GetCoinTextureString(cur.loot or 0) or tostring(cur.loot or 0)))
    return
  elseif msg == "help" then
    print("|cff7fbf3f" .. TITLE .. "|r /trail: export window, /trail chat: summary in chat, /trail session: this session so far, /trail hud: tracker window on/off, /trail minimap: minimap button on/off")
    return
  end
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
  pace = pace, hm = hm, thousands = thousands,
}
