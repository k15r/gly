# Tasks

## 1. Core

- [ ] 1.1 Introduce `GlyIDs` with the new identifiers and `GlyIDs.Legacy` (R1); switch `LinkParser` to `gly://` with `workdash` as a read alias (R4); verify with tests for "Taken-over link" (old URL resolves, opens, relabels), "Pasted old link", canonical links written as `gly://`, and `missingURL`/`missingText` with both schemes
- [ ] 1.2 Add `LegacyMigration` (R2: online backup into a temp file + atomic rename, migrate, rewrite `](workdash://` in `items.body`/`tags.page_body`, copy shared settings when empty, log counts; no-op when the gly store exists); verify with tests on a copy-like fixture for "First start with WorkDash data" (counts, settings, links rewritten, old file unchanged), "Later starts" (no second copy), and no old store at all

## 2. Rename

- [ ] 2.1 Mechanical rename (R5): `git mv` the package to `Packages/GlyCore` and modules/targets/types to `Gly…`; `project.yml` targets, product names, bundle ids, launch agent plist, entitlements (both app groups, R2); MCP server name `gly`; log subsystems; all UI strings; `scripts/build.sh`, `scripts/manual-checks.py`, `docs/`; verify with a clean build of `gly.app`, the full test suite, and `grep -ri workdash Apps Packages scripts docs project.yml` finding only `GlyIDs.Legacy`, the scheme alias and the migration
- [ ] 2.2 Run `LegacyMigration` in the agent before opening the store; verify manually (after the user stopped the WorkDash agent, R3) "Name in the system", "First start with WorkDash data" on the real store, and "WorkDash stopped before the switch"
- [ ] 2.3 Editorial pass over `openspec/specs/**`: product name "WorkDash" → "gly" in prose only; verify `openspec validate --specs --strict` and `grep -r WorkDash openspec/specs` empty

## 3. Switch-over

- [ ] 3.1 Write `docs/manual-checks-rename.md` (data counts before/after, links, settings incl. HTTP token, calendar access re-grant, quick capture, MCP from Claude Code after reconfiguring) and push it as tasks into gly; with the user's permission update the `workdash` entry in `~/.claude.json` to `gly` / `gly-mcp` (R6); done when `pull` reports every check passed

## Workflow follow-up

- Run `/opsx:verify rename-to-gly`, then archive after the manual checks pass; afterwards the user deletes WorkDash.app.
