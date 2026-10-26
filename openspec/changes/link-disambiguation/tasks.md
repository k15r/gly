# Tasks

## 1. Core

- [x] 1.1 Extend `LinkResolver` with kind prefixes and tag-path matching, returning `UnresolvedLink` candidates for ambiguous links; add `CommandOK.unresolvedLinks`; keep missing-link resolution on page creation working with the new forms; verify with tests for "Unique title", "Ambiguous or unknown title", "Tag path", "Kind prefix", "Resolved once", a title containing `/`, and a page created later resolving `[[person/alex/Goals]]`
- [x] 1.2 Implement `Disambiguation.qualifiers` and `DisplayNames.display` (same-kind same-title groups, deepest unique tag, creation-date fallback); verify with tests for "Qualifier appears with a duplicate", "Qualifier follows tag changes", "Same tags", tasks vs pages scoped separately, and a unique title without qualifier
- [x] 1.3 Add `Command.resolveLink(source, typed:, target:)` that rewrites one typed link in a page, task or tag page text to a canonical link (one undo step) and `LinkResolver.candidates(db, typed:)` (read-only); extend `SearchHit` with tags and modified time; verify with tests for "Pick a candidate" and the search fields

## 2. MCP

- [ ] 2.1 Add `unresolved_links` with candidates, `display` + `tags` on links/backlinks, `same_title` on `create_page`, and document prefixes and tag paths in tool descriptions; verify with MCP tests for "Ambiguous link with candidates", "Two Goals pages", and a duplicate `create_page`

## 3. Editor and app

- [ ] 3.1 Extend `LinkAppearance` with kind and qualifier; draw icons (page/task/tag/web/missing) and qualifiers for chips in `WDTextView` using kerning-reserved space; add icon and qualifier to the read view; verify manually "Task link", "Qualifier appears with a duplicate" in editor and read view, and that caret, selection and scrolling around chips still behave (else switch to the documented fallback)
- [ ] 3.2 Use display names and the second line (kind · tags · edited) in the `[[` picker, ⌘K, search results, backlinks and tag page lists, and show duplicates in the pages list as "Title · tag"; verify manually "Pick between same-titled pages" and "Profile pages per person"
- [ ] 3.3 Offer candidates for ambiguous links: an `NSMenu` on ⌘-click in the editor and a menu on click in the read view (candidates, then "Create page …"); verify manually "Pick a candidate" in both modes and one ⌘Z

## 4. End to end

- [ ] 4.1 Manual checks in `docs/manual-checks-links.md`: two "Goals" pages under two person tags, links showing qualifiers that update when retagging, typed `[[person/alex/Goals]]` and `[[task:…]]`, an ambiguous `[[Goals]]` resolved via the menu, and Claude Code writing `[[Goals]]` (gets candidates) then retrying with the tag path; neutral test data only

## Workflow follow-up

- Run `/opsx:verify link-disambiguation`, then archive after the manual checks pass.
