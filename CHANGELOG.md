# Changelog

## 1.3.2-beta

- Now also on Wago Addons.
- Automated tests (busted) for chat parsing, pace and formatting run with every change.

## 1.3.1-beta

- Own minimap and addon list icon.
- Removed everything left from the former name BencepoExport: the data takeover, the `/bx` command, the optional dependency and the `legacy/` and `migration/` folders. Use `/trail` or `/lt`.
- Exports no longer carry the `bencepoExport` marker; the web viewer only reads LevelTrail exports.

## 1.3.0-beta

- Best zone per level: online time and XP per zone and level (`char.zoneLevels`).
- Session recap: kills, quests, deaths and vendor value of the loot per play session; `/trail session` shows the running session in chat.
- Dungeon runs: every visit to a dungeon or raid with time, XP, gold, kills, deaths and loot (`char.dungeons`, last 50).
- Travel time: time on flights and corpse runs, in total and per level (`char.travel`).
- Quest numbers (`char.questStats`: completed, quest log, quests per level) and talent trees with points (`char.talentTrees`).
- Web viewer: level times compared with your other characters, best zone for your level, rested XP, travel time, quests, talents (unspent points), gear (weakest slots), professions (at the cap), reputation, death analysis, last session recap, dungeons.

## 1.2.0-beta

- Minimap button (LibDBIcon, so minimap button collectors can take it): left-click opens the export for the web page, right-click turns the tracker window on or off, drag to move. `/trail minimap` hides or shows it. LevelTrail also appears in the game's addon menu next to the minimap.

## 1.1.0-beta

- Tracker window (`/trail hud`): level progress, time on the level, session and average XP per hour, time to the next level and to 60. Movable, remembers position and visibility per character.
- Pace: XP per hour from the last five full levels (or the session), time to the next level and the level cap, in the export (`char.pace`) and in `/trail chat`.
- Zones: online time, XP and deaths per zone (`char.zones`).
- `/trail help` lists the commands.
- Web viewer: XP per hour, time to 60 from the addon, zones table.
- VendorFloor: if Bencepo's auction house addon VendorFloor is installed, its profit is part of the export (account-wide totals, profit per day, and per play session). The web viewer shows it next to the gold curve. Without VendorFloor nothing changes.
- Play sessions in the web viewer show gold per hour.

## 1.0.0-beta

- First public version: level splits, XP sources, deaths, gold per day, repairs, play sessions, library books (WoW Forever) and a copyable export (`/trail`) for the LevelTrail web viewer at https://bencepo.github.io/leveltrail/
