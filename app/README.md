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

The JavaScript was checked with `node --check` after applying the edits.

## How to apply

Applying needs a Claude session with network access (a session without it
refuses with `session_network_off`; a new chat picks up changed network settings).
Two steps, in this order, because each one publishes a new version:

1. `edit_version` with all 12 edits from `leveling-app-edits.json`,
   `base_version` = the version that is live at that moment.
2. `declare_capabilities` with `{"db":{},"sample":{}}`,
   `base_version` = the version step 1 returned.
   This drops the `Claude Code Remote` / `fire_trigger` permission, which the
   removed sync button no longer needs. `db` and `sample` have to stay, otherwise
   the app loses its database and its sample data.

Checked on 2026-11-11 against live version `1794375855-19a3`: each of the 12
`old_text` strings matches exactly once, and the helpers the new code uses
(`arr`, `esc`, `pct`) are present. The database has no custom rules, so the new
`alts` collection needs none.
