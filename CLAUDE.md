# Notes for Claude

LevelTrail: records a character's leveling run in WoW Forever (Lua 5.1) for the web viewer at bencepo.github.io/leveltrail. Author and rights holder: Bencepo. All rights reserved, no open-source license.

## Layout

- `LevelTrail.lua`: everything in game (snapshot, level splits, XP sources, sessions, deaths, gold, zones, dungeon runs, library books, tracker window, export window, minimap button).
- `web/index.html`: the viewer; copy it to the site repo (`bencepo.github.io/leveltrail/`) on changes.
- `tests/`: busted specs with a WoW mock. `ROADMAP.md`: what is done and what is next.
- `Icons/minimap.tga`: in-game icon from the Bencepo logo family. `media/logo.png`: logo for CurseForge, Wago and the website (not packaged).
- `Libs/`: LibStub, CallbackHandler, LibDataBroker, LibDBIcon, BencepoUI.
- `Libs/BencepoUI` is shared by all Bencepo addons and must be the same file in each (canonical copy: minor 3, Nov 2026, with `UI:ShowLink`, used for "Report a bug"). LibStub loads only the highest minor, so two different copies with the same minor make the result depend on load order. Change it in one repo, bump the minor, copy it to the others.

## How it works

- Data goes to `LevelTrailDB` (data version `VERSION`); the game writes it on /reload and logout. `/trail` shows the export as JSON to paste into the web viewer. Nothing sends input to the game.
- Chat payloads can be secret values in restricted contexts: never touch them (`isSecret`).
- Library book quest IDs come from Questie's Forever data.
- Ben's own character page on the viewer shows his current gear.

## Rules

- English only: UI texts, commands, descriptions. No translations (Ben does not want them), no `Notes-xxXX` in the .toc.
- Minimap button like every Bencepo addon: left-click opens the settings window.
- Tests (`busted`), luacheck and LuaLS run in CI; LuaLS must report zero diagnostics.
- Release: new version heading at the top of `CHANGELOG.md`, push to `main`; the workflow uploads to CurseForge and Wago. Test in game first.
