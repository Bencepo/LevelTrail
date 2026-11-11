# Leveling app changes for LevelTrail

`leveling-app-edits.json` holds the text replacements for the Bencepo Leveling App
(artifact https://claude.ai/artifact/FXZJMqPNKyzVwij4v9eAhS, base version 1794375855-19a3).
Each entry replaces `old_text` with `new_text` once. Apply them in a Claude session that
may edit artifacts ("apply app/leveling-app-edits.json from Bencepo/Export to the
leveling app").

What they change:
- Import accepts LevelTrail exports (`/trail`); other characters go to the collection `alts`
- Character tab: level splits, XP sources, deaths, gold per day and repairs, other characters
- The "Refresh from game" button and the scheduled-sync code are removed
- Texts point to `/trail` instead of `/bexport`
- The import sets the library book count (Progress, Books) from the export

The JavaScript was checked with `node --check` after applying the edits.
