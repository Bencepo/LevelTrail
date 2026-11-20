# Notes for Claude

LevelTrail: records a character's leveling run in WoW Forever (Lua 5.1) for the web viewer at bencepo.github.io/leveltrail. Author and rights holder: Bencepo. All rights reserved, no open-source license.

## Layout

- `LevelTrail.lua`: everything in game (snapshot, level splits, XP sources, sessions, deaths, gold, zones, dungeon runs, library books, tracker window, export window, minimap button).
- `web/index.html`: the viewer; copy it to the site repo (`bencepo.github.io/leveltrail/`) on changes.
- `tests/`: busted specs with a WoW mock. `ROADMAP.md`: what is done and what is next.
- `Icons/minimap.tga`: in-game icon from the Bencepo logo family. `media/logo.png`: logo for CurseForge, Wago and the website (not packaged).
- `Libs/`: LibStub, CallbackHandler, LibDataBroker, LibDBIcon, BencepoUI (bump its LibStub minor on changes).

## How it works

- Data goes to `LevelTrailDB` (data version `VERSION`); the game writes it on /reload and logout. `/trail` shows the export as JSON to paste into the web viewer. Nothing sends input to the game.
- Chat payloads can be secret values in restricted contexts: never touch them (`isSecret`).
- Library book quest IDs come from Questie's Forever data.
- Ben's own character page on the viewer shows his current gear.

## Rules

- UI texts in English, no translations (Ben does not want them).
- Tests (`busted`), luacheck and LuaLS run in CI; LuaLS must report zero diagnostics.
- Release: new version heading at the top of `CHANGELOG.md`, push to `main`; the workflow uploads to CurseForge and Wago. Test in game first.
