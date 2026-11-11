# LevelTrail Roadmap

Status as of 2026-11-11. Goal: the leveling tracker people install alongside Questie, used well beyond one character.

## Now: 1.1.0-beta (released 2026-11-11, in testing)

- [x] Tracker window `/trail hud`: level progress, time on the level, XP per hour, time to the next level and to 60
- [x] Pace in the export and in `/trail chat`
- [x] Time, XP and deaths per zone
- [x] Web viewer: XP per hour, time to 60, zones table
- [x] VendorFloor profit in the export and the web viewer, gold per hour per session
- [ ] Test in game: tracker window, pace after a few levels, zone times
- [ ] Check the list of the 40 library book quests in game (count matches 10/40 so far)
- [x] Release 1.1.0-beta on CurseForge
- [ ] Release 1.1.0 (stable) after the in-game test

## 1.2.0-beta (released)

- [x] Minimap button and addon menu entry

## Next: 1.3 (built, not released)

- [x] Level times compared with your other characters (web viewer)
- [x] Best zone for your level range, from your own XP per hour
- [x] Session recap: kills, quests, deaths, loot value; `/trail session`
- [x] Dungeon runs: time, XP, gold and loot per visit, compared with your usual pace
- [x] Travel time: flights and corpse runs
- [x] Web viewer: rested XP, quests, talents, gear, professions, reputation, death analysis
- [ ] Test in game: dungeon detection, flight times, loot value, talent tree names
- [ ] Release 1.3.0-beta

## After 1.3

- [ ] Tracker options: lock position, scale, choose the lines, hide in combat
- [ ] Leveling app: decide whether it is replaced by the web viewer (the old app artifact no longer exists)
- [ ] German texts in game (deDE), the rest stays English

## Later

- [ ] Support further Classic clients (Classic Era, Hardcore, Season of Discovery) to reach more players
- [ ] Web viewer: compare characters side by side, share card with pace and zones
- [ ] Session recap in chat on logout
- [ ] Stable 1.x release on CurseForge and Wago

## Maintenance (ongoing)

- Weekly code polishing as a scheduled task: luacheck, dead code, naming, small refactors, CI upkeep. Changes come as a pull request, never straight to `main`.
- luacheck stays at 0 warnings.
