# Manual checks: tag-colors

Build and run: `scripts/build.sh && open build/Build/Products/Debug/WorkDash.app`.
Neutral test data only (no real names). Setup: tasks or pages tagged `person/alex`, `person/alex/blargh`, `person/sam`, `project/atlas`; a done task tagged `person/old`; a page "Hub" linking to the tag `person/alex` (via the `[[` picker).

## A. Colors (task 3.1)

- [ ] A1 The tag tree shows a colored dot per tag; chips use the same colors as before (automatic).
- [ ] A2 Right-click `person` → Color → Green → `person`, `person/alex`, `person/alex/blargh`, `person/sam` are green (dots and chips everywhere, e.g. the task list); "Automatic" is unchecked, Green checked ("Color a group").
- [ ] A3 `person/alex` → Orange → it and `person/alex/blargh` are orange, `person/sam` stays green ("Override below").
- [ ] A4 `person/alex` → Automatic → green again; ⌘Z brings orange back ("Back to automatic").
- [ ] A5 Tag page of `person/alex/blargh`: icon and name are in the tag's color; the small square next to it shows the color, its tooltip says "inherited from person/alex" (or "own color" / "automatic"), and its menu changes the color ("Inherited color shown").
- [ ] A6 All palette colors readable as chips in light and dark mode (System Settings → Appearance).

## B. Managing tags (task 3.2)

- [ ] B1 Right-click "Tags" (section header) or any tag → Show Unused Tags → `person/old` appears, greyed with "unused"; its menu offers Color, Rename, Delete; the setting survives a restart ("Tag of finished work").
- [ ] B2 Rename `person` to `people` → `people/alex`, `people/alex/blargh`, `people/sam` with all items; the link on "Hub" reads `people/alex`; ⌘Z restores `person` ("Rename a group").
- [ ] B3 Create a task tagged `person/al`, then rename `person/al` to `person/alex` → "Merge tags?" lists `person/alex`; Merge → the task is under `person/alex`, `person/al` is gone; ⌘Z splits them again ("Merge two spellings").
- [ ] B4 Same rename, Cancel at the merge question → nothing changes ("Merge declined").
- [ ] B5 Delete `project/atlas` → the alert says "Remove … from N items?"; confirm → the items lose the tag, links to it show as deleted; ⌘Z brings it back ("Delete a used tag").
- [ ] B6 On a tag page, "…" → Rename… → the page shows the new name; "…" → Delete… → the page goes back ("Rename from the tag page").

## C. End to end (task 4.1)

- [ ] C1 Quit and reopen WorkDash → colors are kept.
- [ ] C2 Ask Claude Code to make `project/atlas` orange and list the tags → it uses `update_tag_page` with `color: "orange"`; `list_tags` shows `color: orange`, `effective_color: orange`; the app shows it orange.
