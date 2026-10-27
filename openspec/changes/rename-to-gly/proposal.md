# Proposal

## Why

The app gets its real name: **gly** (all lowercase). An app icon already exists; the name still says WorkDash everywhere, from the Dock and menu bar to the identifiers the app, its agent, the MCP bridge and the stored links use. A half rename (new label, old identifiers) would leave "workdash" visible in links, logs, the MCP server name and System Settings. So everything moves to gly, and the data I already have comes along.

## What Changes

- **Name everywhere:** app bundle `gly.app` and the display name "gly" in Dock, Finder, menu bar, windows, menus, Settings, alerts and quick capture. The MCP server announces itself as `gly`.
- **New identifiers:**
  - bundle ids `dev.k15r.gly`, `dev.k15r.gly.agent` and `dev.k15r.gly.mcp`
  - app group `DB33H6YGK7.dev.k15r.gly`
  - the agent's Mach service `DB33H6YGK7.dev.k15r.gly.store-agent` and launch agent `dev.k15r.gly.store-agent`
  - database file `gly.sqlite`
  - link scheme `gly://`
  - CLI bridge `gly-mcp`
- **Data comes along:** on first start, gly copies the WorkDash database and shared settings (working hours, effort sizes, hidden calendars, HTTP access and token) into its own container, and rewrites `workdash://` links in all texts to `gly://`. The WorkDash files stay untouched as a fallback.
- **Old links keep working:** `workdash://` links, pasted or found anywhere later, are read as `gly://`.
- **The old app is retired by hand, once:** before gly's first start, the user stops the WorkDash agent (`launchctl bootout`), removes its login item and later deletes WorkDash.app. gly never writes WorkDash's store.
- **Code and docs:** the Swift package and modules become `GlyCore`, `GlyMCP` and `GlyEditor`, types like `WorkDashIDs` become `GlyIDs`, and the Xcode project and targets are renamed. Scripts, docs and the specs' prose are renamed too.
- **BREAKING for the setup** (once, by hand):
  - grant calendar access again (it's tied to the bundle id)
  - point Claude Code and Joule at `gly.app/.../gly-mcp`, or the new HTTP endpoint with the carried-over token
  - re-enable "Open at login" if used
  - delete WorkDash.app

Not in this change: renaming the repository folder (paths of tooling and memory depend on it), renaming existing tags such as `workdash/checks/…` (user data), migrating back.

## Capabilities

### New Capabilities

- `app-identity`: the product name, carrying over data and settings from WorkDash, retiring the old agent, and reading old link URLs.

### Modified Capabilities

None at the behavior level. The existing specs mention "WorkDash" only as the product's name in prose; that's renamed editorially (no requirement changes).

## Impact

- **Project and build:** `project.yml` (targets, product names, bundle ids, entitlements' app groups), `scripts/build.sh` output path, launch agent plist, the Xcode project regenerated.
- **Core:**
  - `GlyIDs` replaces `WorkDashIDs`
  - `LinkParser.scheme` becomes `gly`, with `workdash` accepted as an alias
  - a new `LegacyMigration`, run by the agent before opening the store: copy, rewrite links, mark done
- **Entitlements:** app and agent list both app groups (the new one, plus the old one for reading during migration). `gly-mcp` needs none.
- **The package directory** `Packages/WorkDashCore` becomes `Packages/GlyCore`; the test targets are renamed too.
- **Docs and scripts:** `scripts/manual-checks.py` (the bridge path), `docs/`, and the specs' prose.
- **The user's environment:** the Claude Code MCP config references the old path; the user updates it (or Claude does, with permission).
