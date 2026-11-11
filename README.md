# LevelTrail

A World of Warcraft: Forever addon that records your leveling and hands it to a companion app.

## What it records

- **Character snapshot**: level, XP, rested XP, gold, zone, bags and free slots, equipped gear and gear in bags (with stats), professions and recipes, quest log and completed quests, talents, reputation, known spells.
- **Level splits**: when each level was reached and how much online time it took.
- **XP sources**: XP from quests, kills and exploration, in total and per level. The rest shows as "other".
- **Play sessions**: duration, XP and gold per session. Sessions older than the last 30 are summed up per month.
- **Deaths**: when, where and at which level.
- **Gold and repairs**: gold per day (last 120 days) and repair costs.
- **Several characters**: each character is kept separately.

Snapshots are taken automatically on level-up, quest turn-in, zone change, gear and gold changes (at most one every two seconds).

## Getting the data out

Type `/trail` (or `/lt`) in the game. A window shows the export as JSON, already selected: press Ctrl+C and paste it into the companion app.
The game also writes everything to `WTF\Account\<ACCOUNT>\SavedVariables\LevelTrail.lua` on `/reload` and on logout.

`/trail chat` prints a one-line summary instead.

## Former name

LevelTrail was called BencepoExport. On the first login it takes over the old data, as long as the `BencepoExport` folder is still installed (the stub in `migration/` is enough). After that the old folder can be deleted.

## Notes

- Online time is counted by the addon from its install on. A level the addon did not see from the start is marked as partial.
- Nothing is sent anywhere: an addon can only write its SavedVariables file and show text.

## License

Copyright (c) 2026 Bencepo. All rights reserved. See [LICENSE](LICENSE).
