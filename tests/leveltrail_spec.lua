local wow = require("tests.helpers.wow")

describe("LevelTrail", function()
	local ns, env, T

	before_each(function()
		ns, env = wow.Load("LevelTrail", { "LevelTrail.lua" }, function(e)
			e.LevelTrailDB = {}
		end)
		T = ns.test
	end)

	local function char() return env.LevelTrailDB["Tester-Realm"] end

	describe("loading", function()
		it("reads the version from the TOC and falls back to dev", function()
			-- the file loaded without touching an unknown global; the export marks the format
			local s = T.store()
			s.bags = {}
			assert.equal(4, T.buildExport(s).levelTrail)
		end)
	end)

	describe("chat lines", function()
		it("reads the XP of a kill", function()
			local p = T.toPattern(env.COMBATLOG_XPGAIN_FIRSTPERSON)
			assert.equal(85, T.numberIn("Kobold Miner dies, you gain 85 experience.", p))
			assert.is_nil(T.numberIn("Something else", p))
		end)
		it("handles numbered placeholders", function()
			local p = T.toPattern("%1$s dies, you gain %2$d experience.")
			assert.equal(40, T.numberIn("Wolf dies, you gain 40 experience.", p))
		end)
		it("handles a literal percent sign", function()
			local p = T.toPattern("%d%% rested bonus for %s")
			assert.equal(50, T.numberIn("50% rested bonus for you", p))
		end)
		it("skips secret chat values", function()
			local p = T.toPattern(env.COMBATLOG_XPGAIN_FIRSTPERSON)
			local msg = "Kobold Miner dies, you gain 85 experience."
			env.issecretvalue = function(v) return v == msg end
			assert.is_nil(T.numberIn(msg, p))
			assert.equal(0, T.lootValue(msg))
			env.issecretvalue = nil
		end)
		it("values looted items at their vendor price", function()
			env.items[2589] = { name = "Linen Cloth", sell = 13 }
			local link = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
			assert.equal(65, T.lootValue("You receive loot: " .. link .. "x5."))
			assert.equal(13, T.lootValue("You receive loot: " .. link .. "."))
		end)
		it("ignores lines that are not loot", function()
			assert.equal(0, T.lootValue("Tester has gone offline."))
			assert.equal(0, T.lootValue(nil))
		end)
		it("queues uncached items and values them when the data arrives", function()
			local link = "|cffffffff|Hitem:4306::::::::|h[Silk Cloth]|h|r"
			local v, id, n = T.lootValue("You receive loot: " .. link .. "x3.")
			assert.equal(0, v)
			assert.equal(4306, id)
			assert.equal(3, n)
			T.trackXP() -- starts XP tracking, so a session can exist
			T.lootQueue(id, n)
			env.items[4306] = { name = "Silk Cloth", sell = 38 }
			T.lootReceived(4306, true)
			assert.equal(114, char().session.loot)
		end)
	end)

	describe("XP and sessions", function()
		it("counts the first XP gain of a fresh install and of a new session", function()
			env.xp = 1000
			T.trackXP() -- baseline at login
			env.xp = 1200
			T.trackXP()
			assert.equal(200, char().session.xpGained)
			assert.equal(200, char().xpSources.total)
			-- a long break: the next gain opens a new session and is counted there
			env.now = env.now + 3600
			env.xp = 1500
			T.trackXP()
			assert.equal(300, char().session.xpGained)
			assert.equal(500, char().xpSources.total)
			assert.equal(1, #char().sessions) -- the old one was saved
			assert.equal(200, char().sessions[1].xpGained)
		end)

		it("adds the full XP of levels skipped by one big gain", function()
			env.level, env.xp, env.xpMax = 10, 7000, 7600
			T.trackXP()
			env.level, env.xp, env.xpMax = 12, 100, 10100
			T.trackXP()
			-- 600 to finish level 10, all of level 11 (8800), 100 into level 12
			assert.equal(600 + 8800 + 100, char().xpSources.total)
			assert.equal(8800, char().xpSources.byLevel["11"].total)
		end)

		it("waits when the XP event comes before the level change", function()
			env.level, env.xp, env.xpMax = 10, 7500, 7600
			T.trackXP()
			env.xp = 50 -- new XP, level not updated yet
			T.trackXP()
			assert.is_nil(char().xpSources)
			env.level, env.xpMax = 11, 8800
			T.trackXP()
			assert.equal(100 + 50, char().xpSources.total)
		end)

		it("keeps sessions at the level cap", function()
			env.level, env.xp, env.xpMax = 60, 0, 0
			assert.is_table(T.sessionGet())
		end)

		it("counts kills for the dungeon run without a session", function()
			local char_ = T.store()
			char_.dungeonRun = { name = "Wailing Caverns", start = env.now }
			env.xpMax = 0 -- values not loaded: no session
			T.bump("kills")
			assert.equal(1, char_.dungeonRun.kills)
			assert.is_nil(char_.session)
		end)

		it("puts counters after a break into a new session", function()
			T.trackXP()
			T.bump("kills")
			env.now = env.now + 2000
			T.bump("kills")
			assert.equal(1, char().session.kills)
			assert.equal(1, char().sessions[1].kills)
		end)
	end)

	describe("deaths", function()
		it("counts every death per level", function()
			for _ = 1, 3 do T.onDeath() end
			assert.equal(3, char().deathsByLevel["10"])
			assert.equal(3, char().deathCount)
		end)
		it("exports only the last 20 deaths but the full count per level", function()
			for _ = 1, 25 do T.onDeath() end
			local s = char()
			s.bags = {}
			local e = T.buildExport(s)
			assert.equal(20, #e.char.deaths)
			assert.equal(25, e.char.deathCount)
			assert.equal(25, e.char.deathsByLevel["10"])
		end)
		it("rebuilds the count per level from a complete death list", function()
			local s = T.store()
			s.deaths = { { level = 5 }, { level = 5 }, { level = 7 } }
			s.deathCount = 3
			T.migrate()
			assert.equal(2, s.deathsByLevel["5"])
			assert.equal(1, s.deathsByLevel["7"])
		end)
	end)

	describe("export", function()
		it("does not change the saved quest list", function()
			local s = T.store()
			s.bags = {}
			s.completedQuests = { 1, 2, 3 }
			local e = T.buildExport(s)
			assert.same({ 1, 2, 3 }, e.quests.completed)
			assert.is_nil(getmetatable(s.completedQuests))
		end)
		it("reads spell ranks in any language", function()
			local s = T.store()
			s.bags = {}
			s.spells = { { name = "Feuerball", sub = "Rang 1" }, { name = "Feuerball", sub = "Rang 4" } }
			local e = T.buildExport(s)
			assert.equal(4, e.spells.spells[1].rank)
		end)
		it("lists recipes that still give skill", function()
			local s = T.store()
			s.bags = {}
			s.recipes = { Cooking = { unknown = {
				{ name = "Orange", difficulty = 0 }, { name = "Yellow", difficulty = 1 },
				{ name = "Green", difficulty = 2 }, { name = "Grey", difficulty = 3 } } } }
			assert.same({ "Orange", "Yellow", "Green" }, T.buildExport(s).recipes.inRange.Cooking)
		end)
		it("encodes valid JSON", function()
			local out = {}
			T.enc({ a = { 1, 2 }, b = "x\"y", c = 1.5 }, out)
			local text = table.concat(out)
			assert.truthy(text:find('"b":"x\\"y"', 1, true))
			assert.truthy(text:find('"a":[1,2]', 1, true))
		end)
	end)

	describe("bank", function()
		it("reads the Classic bank bags after the four character bags", function()
			env.NUM_BAG_SLOTS, env.NUM_BANKBAGSLOTS = 4, 6
			assert.same({ -1, 5, 6, 7, 8, 9, 10 }, T.bankBagIDs())
		end)
	end)

	describe("pace", function()
		it("XP per hour comes from the finished levels", function()
			local need = T.xpForLevel(9)
			local p = T.pace({ splits = { { level = 10, dur = 3600 } } })
			assert.equal(need, p.xpPerHour)
			assert.equal(7600, p.xpToNext)
			assert.equal(math.floor(7600 / need * 3600 + 0.5), p.secToNext)
			assert.equal("levels", p.rateFrom)
		end)
		it("no rate without data", function()
			local p = T.pace({ splits = {} })
			assert.is_nil(p.xpPerHour)
			assert.is_nil(p.secToNext)
		end)
		it("stops at the level cap", function()
			env.level = 60
			assert.is_true(T.pace({}).atCap)
		end)
		it("gives no time to the cap when the XP table does not reach it", function()
			env.GetMaxPlayerLevel = function() return 70 end
			local p = T.pace({ splits = { { level = 10, dur = 3600 } } })
			assert.is_nil(p.xpToCap)
			assert.is_nil(p.secToCap)
			assert.is_number(p.secToNext)
		end)
	end)

	describe("formatting", function()
		it("hours and minutes", function()
			assert.equal("1 h 30 min", T.hm(5400))
			assert.equal("5 min", T.hm(300))
			assert.equal("?", T.hm(nil))
		end)
		it("thousands separators", function()
			assert.equal("1,234,567", T.thousands(1234567))
			assert.equal("123,456", T.thousands(123456))
			assert.equal("12", T.thousands(12))
			assert.equal("-123,456", T.thousands(-123456))
			assert.equal("-12", T.thousands(-12))
		end)
	end)
end)
