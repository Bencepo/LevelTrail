-- Bencepo Export converter: SavedVariables (Lua) -> JSON documents for the leveling app database.
-- usage: texlua convert.lua out_dir file1.lua [file2.lua ...]   (oldest first; last file is the current one)
-- writes out_dir/{char,quests,recipes,spells,equipped}.json for the character named Bencepo (env BENCEPO_CHAR overrides).
local outdir = arg[1]
local CHAR = os.getenv("BENCEPO_CHAR") or "Bencepo"
local function enc(v, out)
  local t = type(v)
  if t == "nil" then out[#out+1] = "null"
  elseif t == "boolean" then out[#out+1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out+1] = "null"
    elseif math.type and math.type(v) == "integer" then out[#out+1] = string.format("%d", v)
    else out[#out+1] = string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "") end
  elseif t == "string" then
    out[#out+1] = '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" else return string.format("\\u%04x", c:byte()) end end) .. '"'
  elseif t == "table" then
    local n = #v
    local mt = getmetatable(v)
    local isArr = n > 0 or (mt and mt.__arr) or false
    if isArr then for k in pairs(v) do if type(k) ~= "number" then isArr = false break end end end
    if isArr then
      out[#out+1] = "["
      for i = 1, n do if i > 1 then out[#out+1] = "," end enc(v[i], out) end
      out[#out+1] = "]"
    else
      out[#out+1] = "{"
      local keys = {}
      for k in pairs(v) do keys[#keys+1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for i, k in ipairs(keys) do
        if i > 1 then out[#out+1] = "," end
        enc(tostring(k), out) out[#out+1] = ":" enc(v[k], out)
      end
      out[#out+1] = "}"
    end
  end
end
local function A(t) return setmetatable(t or {}, { __arr = true }) end
local function write(name, v)
  local out = {} enc(v, out)
  local f = assert(io.open(outdir .. "/" .. name .. ".json", "w")) f:write(table.concat(out)) f:close()
end
local STAT = { ITEM_MOD_STRENGTH_SHORT="str", ITEM_MOD_AGILITY_SHORT="agi", ITEM_MOD_STAMINA_SHORT="sta", ITEM_MOD_INTELLECT_SHORT="int",
  ITEM_MOD_SPIRIT_SHORT="spi", ITEM_MOD_ATTACK_POWER_SHORT="ap", RESISTANCE0_NAME="armor", ITEM_MOD_DAMAGE_PER_SECOND_SHORT="dps" }
local NOTE = { ITEM_MOD_DEFENSE_SKILL_RATING_SHORT="Defense", ITEM_MOD_FIRE_RESISTANCE_SHORT="Fire Resistance", ITEM_MOD_NATURE_RESISTANCE_SHORT="Nature Resistance",
  ITEM_MOD_FROST_RESISTANCE_SHORT="Frost Resistance", ITEM_MOD_SHADOW_RESISTANCE_SHORT="Shadow Resistance", ITEM_MOD_ARCANE_RESISTANCE_SHORT="Arcane Resistance",
  ITEM_MOD_MANA_REGENERATION_SHORT="mana regeneration", ITEM_MOD_SPELL_POWER_SHORT="spell power", ITEM_MOD_HERBALISM_SHORT="Herbalism",
  ITEM_MOD_CRIT_RATING_SHORT="Crit", ITEM_MOD_HIT_RATING_SHORT="Hit", ITEM_MOD_DODGE_RATING_SHORT="Dodge", ITEM_MOD_HEALTH_REGENERATION_SHORT="health regeneration" }
local function gear(it)
  local o = { name = it.name, ilvl = it.ilvl, wid = it.id, loc = it.equipLoc }
  local q = tostring(it.link or ""):match("|cnIQ(%d)")
  if q then o.q = tonumber(q) end
  local notes = {}
  for k, v in pairs(it.stats or {}) do
    if STAT[k] then o[STAT[k]] = (STAT[k] == "dps") and (math.floor(v * 100 + 0.5) / 100) or v
    elseif NOTE[k] then notes[#notes+1] = "+" .. tostring(v) .. " " .. NOTE[k]
    elseif not k:match("^RESISTANCE") then notes[#notes+1] = "+" .. tostring(v) .. " " .. k:gsub("ITEM_MOD_", ""):gsub("_SHORT", ""):gsub("_", " "):lower() end
  end
  table.sort(notes)
  if #notes > 0 then o.note = table.concat(notes, ", ") end
  return o
end
local FORM = { [0] = "Caster", [1] = "Bear", [2] = "Aquatic", [3] = "Cat", [4] = "Travel" }
local sheets = {}
local s
for i = 2, #arg do
  BencepoExportDB = nil
  dofile(arg[i])
  local c
  for k, v in pairs(BencepoExportDB) do if k:match("^" .. CHAR .. "%-") then c = v end end
  if not c then error("character " .. CHAR .. " not found in " .. arg[i]) end
  s = c
  if s.sheet and s.sheet.form ~= nil then
    local sh = {}
    for k, v in pairs(s.sheet) do if k ~= "form" then sh[k] = type(v) == "number" and (math.floor(v * 100 + 0.5) / 100) or v end end
    sh.date = s.date
    sheets[FORM[s.sheet.form] or ("Form " .. tostring(s.sheet.form))] = sh
  end
end
local items = {}
for id, c in pairs(s.items or {}) do items["i" .. id] = c end
local bagGear = A()
for _, g in ipairs(s.bagGear or {}) do bagGear[#bagGear+1] = gear(g) end
local equipped = {}
for slot, it in pairs(s.equipped or {}) do if slot ~= "shirt" and slot ~= "tabard" then equipped[slot] = gear(it) end end
local sessions = A()
for _, x in ipairs(s.sessions or {}) do
  -- drop the records damaged by the logout bug of addon 2.0 (xp jump with 0 minutes)
  if not (x.minutes == 0 and (x.xpGained or 0) > 5000) then sessions[#sessions+1] = x end
end
local talents = A()
for _, t in ipairs((s.talents or {}).list or {}) do talents[#talents+1] = { name = t.name, rank = t.rank, max = t.max } end
write("char", { date = s.date, addonVersion = s.version, level = s.level, xp = s.xp, xpMax = s.xpMax, rested = s.rested, copper = s.copper,
  zone = s.zone, subzone = s.subzone, hearth = s.hearth, bags = { s.bags[1], s.bags[2], s.bags[3], s.bags[4] }, backpack = s.bags.backpack,
  reagentBag = s.reagentBag, freeSlots = s.freeSlots, professions = s.professions, reputation = A(s.reputation), sheets = sheets,
  sessions = sessions, items = items, bagGear = bagGear, talents = talents, unspent = s.talents and s.talents.unspent,
  bank = s.bank and { date = s.bank.date, kinds = s.bank.kinds } or nil })
local log = A()
for _, q in ipairs(s.questLog or {}) do
  local objs = A()
  for _, o in ipairs(q.objectives or {}) do objs[#objs+1] = { text = o.text, done = o.done } end
  log[#log+1] = { id = q.id, title = q.title, level = q.level, complete = q.complete, objectives = objs }
end
write("quests", { date = s.date, log = log, completed = A(s.completedQuests) })
local known, open = {}, {}
for prof, r in pairs(s.recipes or {}) do
  known[prof] = A()
  for _, x in ipairs(r.known or {}) do known[prof][#known[prof]+1] = x.name end
  open[prof] = A()
  for _, x in ipairs(r.unknown or {}) do if (x.difficulty or 0) > 0 then open[prof][#open[prof]+1] = x.name end end
end
write("recipes", { date = s.date, known = known, inRange = open })
local best, order = {}, {}
for _, sp in ipairs(s.spells or {}) do
  local r = tonumber((sp.sub or ""):match("Rank (%d+)")) or 0
  if not best[sp.name] then best[sp.name] = { name = sp.name, rank = r, tab = sp.tab } order[#order+1] = sp.name
  elseif r > best[sp.name].rank then best[sp.name].rank = r end
end
local spells = A()
for _, n in ipairs(order) do spells[#spells+1] = best[n] end
write("spells", { date = s.date, spells = spells })
write("equipped", equipped)
print(s.date, "level", s.level, "copper", s.copper, "quests", #log, "spells", #spells, "talents", #talents)
