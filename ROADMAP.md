# LevelTrail Roadmap

Status as of 2026-11-11. Goal: the leveling tracker people install alongside Questie, used well beyond one character.

## Now: 1.1 (in testing)

- [x] Tracker window `/trail hud`: level progress, time on the level, XP per hour, time to the next level and to 60
- [x] Pace in the export and in `/trail chat`
- [x] Time, XP and deaths per zone
- [x] Web viewer: XP per hour, time to 60, zones table
- [ ] Test in game: tracker window, pace after a few levels, zone times
- [ ] Check the list of the 40 library book quests in game (count matches 10/40 so far)
- [ ] Release 1.1.0-beta on CurseForge

## Next: 1.2

- [ ] Tracker options: lock position, scale, choose the lines, hide in combat
- [ ] Split comparison: current level against your average and your best character at the same level
- [ ] Best zone hint: XP per hour per zone for your level range, from your own data
- [ ] Leveling app: zones and pace in the Character tab
- [ ] German texts in game (deDE), the rest stays English

## Later

- [ ] Support further Classic clients (Classic Era, Hardcore, Season of Discovery) to reach more players
- [ ] Web viewer: compare characters side by side, share card with pace and zones
- [ ] Session recap on logout: time, XP, levels and gold of the session in chat
- [ ] Stable 1.x release on CurseForge and Wago

## Maintenance (ongoing)

- Weekly code polishing as a scheduled task: luacheck, dead code, naming, small refactors, CI upkeep. Changes come as a pull request, never straight to `main`.
- luacheck stays at 0 warnings.
