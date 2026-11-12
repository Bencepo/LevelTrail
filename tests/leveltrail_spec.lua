local wow = require("tests.helpers.wow")

describe("LevelTrail", function()
	local ns, env, T

	before_each(function()
		ns, env = wow.Load("LevelTrail", { "LevelTrail.lua" }, function(e)
			e.LevelTrailDB = {}
			e.GetMaxPlayerLevel = function() return 60 end
			e.UnitLevel = function() return 10 end
			e.UnitXP = function() return 0 end
			e.UnitXPMax = function() return 7600 end
		end)
		T = ns.test
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
		it("values looted items at their vendor price", function()
			env.items[2589] = { name = "Linen Cloth", sell = 13 }
			local link = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
			assert.equal(65, T.lootValue("You receive loot: " .. link .. "x5."))
			assert.equal(13, T.lootValue("You receive loot: " .. link .. "."))
			assert.equal(0, T.lootValue("You receive loot: nothing known."))
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
			env.UnitLevel = function() return 60 end
			assert.is_true(T.pace({}).atCap)
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
		end)
	end)
end)
