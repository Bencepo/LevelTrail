# LevelTrail Roadmap

Status as of 2026-11-14. Goal: the leveling tracker people install alongside Questie, used well beyond one character.

## Released

- 1.0.0-beta to 1.3.6-beta: level splits, XP sources, sessions, deaths, gold, library books, tracker window, pace, zones, minimap button, dungeon runs, travel time, session recap, web viewer insights, own icon, Wago, automated tests and code checks

## Now: 1.4.0-beta

- [x] Fixes from the code review of 2026-11-14 (GitHub issues #10 to #52): XP and sessions, dungeon visits, bank and reputation scans, web viewer safety and accuracy, release workflow
- [x] "Report a bug" button in the export window, `/trail bug`
- [ ] Test in game: sessions across a break, multi-level XP, dungeon corpse run, bank bags, reputation with collapsed headers, Report a bug window
- [ ] Copy `web/index.html` to the site repo

## Next

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
