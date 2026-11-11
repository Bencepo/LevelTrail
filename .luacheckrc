-- luacheck configuration for LevelTrail (WoW Forever, Lua 5.1)
std = "lua51"
max_line_length = false
codes = true

-- Reading WoW API globals (113) is not reported: there are too many to list.
-- Writing globals is, so a typo cannot create a new global without notice.
ignore = { "113", "212/self" }

globals = {
	"LevelTrailDB",
	"SLASH_LEVELTRAIL1",
	"SLASH_LEVELTRAIL2",
	"SLASH_LEVELTRAIL3",
	"SlashCmdList",
}

exclude_files = { "legacy/**", ".release/**" }
