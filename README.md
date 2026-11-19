# LevelTrail

A World of Warcraft: Forever addon that records your leveling run. See it at **https://bencepo.github.io/leveltrail/**: paste the export, and the page shows time per level, XP sources, deaths, gold, library books, your alts and a share image. The page runs in your browser and uploads nothing.

## What it records

- **Character snapshot**: level, XP, rested XP, gold, zone, bags and free slots, equipped gear and gear in bags (with stats), professions and recipes, quest log and completed quests, talents, reputation, known spells.
- **Level splits**: when each level was reached and how much online time it took.
- **XP sources**: XP from quests, kills and exploration, in total and per level. The rest shows as "other".
- **Play sessions**: duration, XP and gold per session. Sessions older than the last 30 are summed up per month.
- **Deaths**: when, where and at which level. Every death is counted per level and per zone; the export carries the details of the last 20.
- **Gold and repairs**: gold per day (last 120 days) and repair costs.
- **Pace**: XP per hour from your last five full levels and from the current session, and the online time still needed for the next level and for level 60.
- **Zones**: online time, XP and deaths per zone.
- **Best zone per level**: online time and XP per zone and level, so the web viewer can show where you level fastest.
- **Session recap**: kills, quests, deaths and loot value per play session (`/trail session` for the running one).
- **Dungeon runs**: time, XP, gold, kills, deaths and loot per dungeon or raid visit.
- **Travel time**: time on flights and corpse runs.
- **Library books** (WoW Forever): which of the 40 books are handed in and which reward quests (10, 20, 25 books) are done, read from the completed quests, so books handed in before the install count too.
- **VendorFloor** (optional): with Bencepo's VendorFloor installed, its flip profit is part of the export.
- **Several characters**: each character is kept separately.

The character snapshot is rebuilt two seconds after a level-up or zone change, at logout and when the export opens. Frequent events (XP, loot, gold, bags, quests) only mark it as stale; it is then rebuilt at most once a minute.

## Getting the data out

Type `/trail` (or `/lt`) in the game. A window shows the export as JSON, already selected: press Ctrl+C and paste it at https://bencepo.github.io/leveltrail/ (or into any app that reads the format).
The game also writes everything to `WTF\Account\<ACCOUNT>\SavedVariables\LevelTrail.lua` on `/reload` and on logout.

`/trail chat` prints a one-line summary instead, including your pace.

## Tracker window

`/trail hud` turns a small window on or off: level progress, time on the current level, XP per hour (session and recent levels) and the time to the next level and to the level cap. Drag it anywhere; position and visibility are kept per character.

`/trail options` (or shift-click the minimap button) opens the tracker options in their own window: lock the position (clicks then go through), hide it in combat, size, background opacity, and which lines to show. Every change shows at once.

## Minimap button and commands

The minimap button (also in the game's addon menu next to the minimap) opens the export with a left-click and turns the tracker window on or off with a right-click; shift-click opens the tracker options. `/trail minimap` hides or shows it.

| Command | What it does |
|---|---|
| `/trail` or `/lt` | export window |
| `/trail chat` | one-line summary in chat |
| `/trail session` | the running play session |
| `/trail hud` | tracker window on or off |
| `/trail options` | tracker options window |
| `/trail minimap` | minimap button on or off |
| `/trail bug` | link for a bug report (also the "Report a bug" button in the export window) |
| `/trail help` | list of commands |

## Web viewer

The page lives in `web/index.html` and is published from the public repo `Bencepo/bencepo.github.io` (folder `leveltrail/`). After changing it, copy the file there and push.

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## Notes

- Online time is counted by the addon from its install on. A level the addon did not see from the start is marked as partial.
- Nothing is sent anywhere: an addon can only write its SavedVariables file and show text.

## Feedback and bug reports

Found a bug or have an idea? [Open an issue](https://github.com/Bencepo/LevelTrail/issues/new/choose), it takes a minute. For bugs the Lua error text (from BugSack, or `/console scriptErrors 1`) and your LevelTrail version help the most. No GitHub account? Comment on [CurseForge](https://www.curseforge.com/wow/addons/leveltrail#comments). Every report gets read.

## More addons by Bencepo

All addons, live demos and the web pages: **https://bencepo.github.io**

Like the addons? Support them on Ko-fi: **https://ko-fi.com/bencepo**

- [VendorFloor](https://bencepo.github.io/vendorfloor/): auction house sniper for finds below vendor price, below disenchant value and profitable crafts.
- [ProcFlare](https://bencepo.github.io/procflare/): big Clearcasting alert and small icons for weapon, trinket and talent procs, with melee and caster sound packs.
- [SwingCast](https://bencepo.github.io/swingcast/): spell icon, cast time, latency zone and a swing timer on the standard cast bar.
- [StatTrim](https://bencepo.github.io/stattrim/): hide, merge and reorder stats right inside the character window.

## AI disclosure

The code was written with the help of an AI assistant (Claude). Bencepo designed the features, tests everything in game and maintains the addon.

## License

Copyright (c) 2026 Bencepo. All rights reserved. See [LICENSE](LICENSE).
