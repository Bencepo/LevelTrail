# Leveling app changes for LevelTrail

`leveling-app-edits.json` holds the text replacements for the Bencepo Leveling App
(artifact https://claude.ai/artifact/4cwBMXj4jj5re8ipVDcFS7, slug
1d4fd62d-31ea-4e3c-a66a-08fd2d54eca0).

**Status: all edits are applied** (artifact version 1794412025-9166, 2026-11-11).
That version also removes the leftover `claude.use("mcp")` call and the unused
`syncBusy`/`syncMsg` variables.

Each entry replaces `old_text` with `new_text` once. When applying again, skip an entry
whose `new_text` is already in the page (some `old_text` values are part of their own
`new_text`). Edits need a Claude session with network access enabled; otherwise the
artifact server refuses changes to existing artifacts.

What they change:
- Import accepts LevelTrail exports (`/trail`); other characters go to the collection `alts`
- Character tab: level splits, XP sources, deaths, gold per day and repairs, other characters
- The "Refresh from game" button and the scheduled-sync code are removed
- Texts point to `/trail` instead of `/bexport`
- The import sets the library book count (Progress, Books) from the export

The JavaScript was checked with `node --check` after applying the edits.
