-- LevelTrail
-- Copyright (c) 2026 Bencepo. All rights reserved. See LICENSE.
--
-- Records a character's leveling into SavedVariables: a snapshot of the character
-- (gold, bags, gear, professions, quests, talents, reputation) plus a history of
-- level splits, XP sources, play sessions, deaths, gold and repairs.
-- /trail shows everything as JSON to copy into a companion app.
-- The game writes the file on /reload and on logout:
--   WTF\Account\<ACCOUNT>\SavedVariables\LevelTrail.lua
-- Nothing here sends input to the game; it only reads.
LevelTrailDB = LevelTrailDB or {}

local ADDON = ...
local VERSION = 6 -- data version
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
local clockLast
local function clockTick()
  local s = store()
  local now = time()
  if clockLast then
    local d = now - clockLast
    if d > 0 and d <= 600 then s.online = (s.online or 0) + d end
  end
  clockLast = now
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
      local tree = { talents = {} }
      local n = try(GetNumTalents, tab) or 0
      for i = 1, n do
        local name, _, tier, column, rank, maxRank = try(GetTalentInfo, tab, i)
        if name and (rank or 0) > 0 then
          tree.talents[#tree.talents + 1] = { name = name, tier = tier, column = column, rank = rank, max = maxRank }
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

---------------------------------------------------------------- sessions (xp and gold per play session)
-- The current session lives in the saved data so a /reload continues it.
local function sessionGet()
  local s = store()
  local xpMax = UnitXPMax("player") or 0
  if xpMax == 0 then return nil end            -- values not loaded yet (login/logout)
  local cur = s.session
  if not cur or (time() - (cur.last or 0)) > 900 then
    cur = { start = time(), date = date("%Y-%m-%d %H:%M"), level = UnitLevel("player"),
      copper = GetMoney() or 0, xpGained = 0, lastXP = UnitXP("player") or 0, lastMax = xpMax, lastLevel = UnitLevel("player") }
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
    xpGained = cur.xpGained, copperDelta = (GetMoney() or 0) - cur.copper }
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
  "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM", "MERCHANT_SHOW", "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY" }
for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end

local bankOpen = false
f:RegisterEvent("BANKFRAME_CLOSED")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == ADDON then pcall(migrate) end
  elseif event == "PLAYER_LOGIN" then
    pcall(snapshot)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() pcall(clockTick) end) end
  elseif event == "PLAYER_LOGOUT" then
    pcall(clockTick)
  elseif event == "PLAYER_LEVEL_UP" then
    pcall(onLevelUp, ...)
    scheduleSnapshot()
  elseif event == "QUEST_TURNED_IN" then
    local questID, xpReward = ...
    pcall(addXP, UnitLevel("player"), "quest", xpReward)
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
    if n then pcall(addXP, UnitLevel("player"), "kill", n) end
  elseif event == "CHAT_MSG_SYSTEM" then
    local n = numberIn(..., EXPLORE_PATTERN)
    if n then pcall(addXP, UnitLevel("player"), "explore", n) end
  elseif event == "PLAYER_DEAD" then
    pcall(onDeath)
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
  local equipped = {}
  for slot, it in pairs(s.equipped or {}) do
    if slot ~= "shirt" and slot ~= "tabard" then equipped[slot] = gearOut(it) end
  end
  local sessions = A()
  for _, x in ipairs(s.sessions or {}) do sessions[#sessions + 1] = x end
  local talents = A()
  for _, t in ipairs((s.talents or {}).list or {}) do talents[#talents + 1] = { name = t.name, rank = t.rank, max = t.max } end
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
  local char = { name = s.name, realm = s.realm, class = s.class, race = s.race, date = s.date, ts = s.ts,
    addonVersion = s.version, level = s.level, xp = s.xp, xpMax = s.xpMax,
    online = s.online, splits = splits, levelSince = s.levelSince, xpSources = s.xpSources,
    deaths = deaths, deathCount = s.deathCount or #allDeaths, goldDays = goldDays, repairs = s.repairs,
    sessionMonths = months, libraryBooks = s.libraryBooks,
    rested = s.rested, copper = s.copper, zone = s.zone, subzone = s.subzone, hearth = s.hearth,
    bags = A({ s.bags[1] or 0, s.bags[2] or 0, s.bags[3] or 0, s.bags[4] or 0 }), backpack = s.bags.backpack,
    reagentBag = s.reagentBag, freeSlots = s.freeSlots, professions = s.professions, reputation = rep, sheets = sheets,
    sessions = sessions, items = items, bagGear = bagGear, talents = talents, unspent = s.talents and s.talents.unspent,
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
  local spells = A()
  for _, n in ipairs(order) do spells[#spells + 1] = best[n] end
  return { levelTrail = 2, bencepoExport = 1, char = char,
    quests = { date = s.date, log = log, completed = A(s.completedQuests) },
    recipes = { date = s.date, known = known, inRange = open },
    spells = { date = s.date, spells = spells },
    equipped = equipped }
end

local exportFrame
local function showExport(text, summary)
  if not exportFrame then
    local f = CreateFrame("Frame", "LevelTrailFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(560, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText(TITLE)
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.info:SetPoint("TOPLEFT", 14, -30)
    f.info:SetPoint("RIGHT", -40, 0)
    f.info:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local scroll = CreateFrame("ScrollFrame", "LevelTrailScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(500)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- keep the text unchanged and selected so Ctrl+C always copies everything
    edit:SetScript("OnTextChanged", function(self, user)
      if user and f.text then self:SetText(f.text) self:HighlightText() end
    end)
    edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    exportFrame = f
  end
  exportFrame.text = text
  exportFrame.info:SetText((summary or "") .. "\nPress Ctrl+C, then paste it at bencepo.github.io/leveltrail. Esc closes.")
  exportFrame.edit:SetText(text)
  exportFrame:Show()
  exportFrame.edit:SetFocus()
  exportFrame.edit:HighlightText()
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
