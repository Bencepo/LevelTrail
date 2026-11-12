# LevelTrail

A World of Warcraft: Forever addon that records your leveling run. See it at **https://bencepo.github.io/leveltrail/**: paste the export, and the page shows time per level, XP sources, deaths, gold, library books, your alts and a share image. The page runs in your browser and uploads nothing.

## What it records

- **Character snapshot**: level, XP, rested XP, gold, zone, bags and free slots, equipped gear and gear in bags (with stats), professions and recipes, quest log and completed quests, talents, reputation, known spells.
- **Level splits**: when each level was reached and how much online time it took.
- **XP sources**: XP from quests, kills and exploration, in total and per level. The rest shows as "other".
- **Play sessions**: duration, XP and gold per session. Sessions older than the last 30 are summed up per month.
- **Deaths**: when, where and at which level.
- **Gold and repairs**: gold per day (last 120 days) and repair costs.
- **Pace**: XP per hour from your last five full levels and from the current session, and the online time still needed for the next level and for level 60.
- **Zones**: online time, XP and deaths per zone.
- **Best zone per level**: online time and XP per zone and level, so the web viewer can show where you level fastest.
- **Session recap**: kills, quests, deaths and loot value per play session (`/trail session` for the running one).
- **Dungeon runs**: time, XP, gold, kills, deaths and loot per dungeon or raid visit.
- **Travel time**: time on flights and corpse runs.
- **Library books** (WoW Forever): which of the 40 books are handed in and which reward quests (10, 20, 25 books) are done, read from the completed quests, so books handed in before the install count too.
- **Several characters**: each character is kept separately.

Snapshots are taken automatically on level-up, quest turn-in, zone change, gear and gold changes (at most one every two seconds).

## Getting the data out

Type `/trail` (or `/lt`) in the game. A window shows the export as JSON, already selected: press Ctrl+C and paste it at https://bencepo.github.io/leveltrail/ (or into any app that reads the format).
The game also writes everything to `WTF\Account\<ACCOUNT>\SavedVariables\LevelTrail.lua` on `/reload` and on logout.

`/trail chat` prints a one-line summary instead, including your pace.

## Tracker window

`/trail hud` turns a small window on or off: level progress, time on the current level, XP per hour (session and recent levels) and the time to the next level and to 60. Drag it anywhere; position and visibility are kept per character. `/trail help` lists all commands.

## Web viewer

The page lives in `web/index.html` and is published from the public repo `Bencepo/bencepo.github.io` (folder `leveltrail/`). After changing it, copy the file there and push.

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## Notes

- Online time is counted by the addon from its install on. A level the addon did not see from the start is marked as partial.
- Nothing is sent anywhere: an addon can only write its SavedVariables file and show text.

## License

Copyright (c) 2026 Bencepo. All rights reserved. See [LICENSE](LICENSE).
