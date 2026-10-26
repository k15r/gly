# Tasks

## 1. Core

- [x] 1.1 Add `TrashQueries.list(db, since:)` and the older-count (T1): deleted pages and tasks newest first, with deleted-at, writer, the tags tombstoned in the delete batch and an excerpt; plus `WriterName.display` (T3); verify with tests for "Agent deletes a page" (entry fields), "Older deletes" (30-day split and count), a task and a page from different writers, and an item without a delete entry
- [x] 1.2 Add `Command.restore(id:)` (T2) that reverts only the item's delete batch as a new change of the current writer, with the label "Restore page/task “…”"; verify with tests for "Restore an agent's delete" (fields, tags, links work again, search finds it), "Undo a restore", "Delete and restore later" (other changes stay), tag assignments removed before the delete stay removed, and not-found for live and unknown ids

## 2. MCP

- [x] 2.1 Add `list_trash` and `restore` (T6) with descriptions, attribution, the "in the trash" hint on `get_page`/`get_task` for deleted ids, and the updated tool list; verify with MCP tests for "Agent undoes its own delete", "Restore something that isn't deleted" and "Agent discovers the tools"

## 3. Editor and app

- [ ] 3.1 Generalize `MissingLinkMenu` into `LinkMenu` driven by a `linkMenu` closure (T5): replacements and actions; missing links keep today's entries; deleted links get Restore (with "deleted … by …"), same-titled relink entries and Show in Trash in the editor (⌘-click) and the read view (click); `MarkdownBlocks.pin` by target; verify with an editor test for the read-view rewrite and manually that missing-link menus are unchanged
- [ ] 3.2 Add the Trash destination (T4): sidebar row with the 30-day count, list with icon, title, tags, excerpt and "deleted … by …", read-only preview, Restore button and row context menu, "Show older (n)"; `LinkOpener` handles `restore` and `trash` URLs; verify manually "Preview", "Restore from the Trash" and the undo overlay label

## 4. End to end

- [ ] 4.1 Manual checks in `docs/manual-checks-trash.md` (neutral test data): delete a page and a task in the app and via Claude Code, find both in the Trash with the right "by"; restore each; ⌘Z after a restore; "Restore from a broken link"; "Link to the surviving duplicate" with one ⌘Z; Show in Trash from a link; an agent restoring its own delete via `list_trash` + `restore`

## Workflow follow-up

- Run `/opsx:verify trash-bin`, then archive after the manual checks pass.
