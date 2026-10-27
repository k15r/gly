# Design

## Context

- **`WorkDashIDs`** (`Packages/WorkDashCore/Sources/WorkDashCore/WorkDashCore.swift`) holds the identities:
  - team `DB33H6YGK7`
  - app group `DB33H6YGK7.dev.k15r.workdash`
  - Mach service `DB33H6YGK7.dev.k15r.workdash.store-agent`
  - launch agent plist `dev.k15r.workdash.store-agent.plist`
  - database `workdash.sqlite`
- **The store** lives in the app-group container. `StoreFactory.openReadWrite` is used by the agent only. Shared settings are `UserDefaults(suiteName: appGroup)`.
- **Targets** (`project.yml`): `WorkDash` (`dev.k15r.workdash`), `WorkDashAgent` (`.agent`, registered via `SMAppService.agent(plistName:)`), and `wd-mcp` (`.mcp`, unsandboxed). The package is `Packages/WorkDashCore` with modules `WorkDashCore`, `WorkDashMCP` and `WorkDashEditor`, plus tests.
- **Links** are stored as `[label](workdash://item|tag/<uuid>)` (`LinkParser.scheme`). Missing links use `workdash://missing/…` at runtime only.
- **App-local preferences** (capture shortcut, menu bar icon) are in the app's own `UserDefaults` domain, inside its sandbox container.
- **Calendar access** (TCC) is granted per bundle id, for the agent.

Motivation is in `proposal.md`, behavior in `specs/app-identity/spec.md`.

## Goals / Non-Goals

**Goals:**
- **Lose nothing:** the WorkDash data and settings arrive in gly on the first start; WorkDash's files stay untouched.
- **No "workdash" left** in identifiers, UI, the MCP server name, code or docs, except:
  - the migration code, which has to name the old ids
  - the link-scheme alias
  - existing user data like tags

**Non-Goals:**
- Renaming the repo folder.
- Migrating app-local preferences: they reset to defaults (shortcut ⌃⌥Space, menu bar icon shown). That's cheap to redo and not reachable across sandbox containers.
- Rewriting history entries.
- A way back to WorkDash.

## Decisions

### R1: Identifiers

`GlyIDs` replaces `WorkDashIDs`:

| | old | new |
|---|---|---|
| app bundle id | `dev.k15r.workdash` | `dev.k15r.gly` |
| agent bundle id | `dev.k15r.workdash.agent` | `dev.k15r.gly.agent` |
| CLI bundle id / product | `dev.k15r.workdash.mcp` / `wd-mcp` | `dev.k15r.gly.mcp` / `gly-mcp` |
| app group | `DB33H6YGK7.dev.k15r.workdash` | `DB33H6YGK7.dev.k15r.gly` |
| Mach service | `….workdash.store-agent` | `DB33H6YGK7.dev.k15r.gly.store-agent` |
| launch agent label / plist | `dev.k15r.workdash.store-agent` | `dev.k15r.gly.store-agent` |
| database file | `workdash.sqlite` | `gly.sqlite` |
| link scheme | `workdash` | `gly` (`workdash` read as alias) |
| MCP server name | `workdash` | `gly` |
| log subsystem | `dev.k15r.workdash…` | `dev.k15r.gly…` |

`GlyIDs.Legacy` keeps the old values the migration needs: app group and database file name.

### R2: Takeover on first start (`LegacyMigration`, in the agent)

It runs in the agent before `StoreFactory.openReadWrite`:
1. **Condition:** the new store file doesn't exist, and `<legacy container>/workdash.sqlite` does. Otherwise it does nothing; an existing gly store means the takeover is done.
2. **Copy the database** with SQLite's online backup (GRDB `backup(to:)`), from a read-only connection to the old file into a temporary file in the new container, then rename it into place. The backup is consistent even if the old agent is still running. The rename is atomic, so a crash leaves no half store.
3. **Open and migrate** the copy normally (schema migrations are idempotent).
4. **Rewrite links** in one transaction, as plain SQL outside the change log: `items.body` and `tags.page_body`, replacing `](workdash://` with `](gly://`. History entries keep their old text; undoing to such a state is still read through the alias (R4).
5. **Copy shared settings:** every key of `UserDefaults(suiteName: Legacy.appGroup)` into the new suite, if the new suite has no `http…`/`working…` keys yet. Then synchronize.
6. **Log** a notice with counts: items, tags, rewritten texts.

**Entitlements:** app and agent both list the new and the old app group. The old one is only read, during the takeover. The old group can be dropped from the entitlements in a later release.

**Alternative considered:** moving the old file. Rejected: copying keeps WorkDash's data as a fallback until the user deletes it.

### R3: Retiring WorkDash (manual, once)

A sandboxed app can't unregister or stop another app's launch agent: `SMAppService` only covers its own bundle, and `launchctl` isn't available in the sandbox. As a one-time switch-over, the user does it by hand before gly's first start:
1. Quit WorkDash.
2. `launchctl bootout gui/$(id -u)/dev.k15r.workdash.store-agent`
3. Remove "WorkDash" under System Settings → General → Login Items → Allow in the Background.
4. Delete WorkDash.app after the checks.

gly never opens the WorkDash store for writing; the takeover reads it once. There's no in-app notice: it would be code for a one-time event.

### R4: Link scheme

`LinkParser.scheme = "gly"`, plus `legacySchemes = ["workdash"]`:
- **Parsing:** `links(in:)` matches both schemes.
- **Writing:** `canonical(...)` always writes `gly://`.
- **Everything else** compares by target (`ParsedLink.Target`): `ParsedLink.Target(url:)`, `destination(for:)`, `missingText` and `missingURL`. So an old URL behaves like a new one.
- **Tests:** a `workdash://` link resolves, shows and opens like a `gly://` one; `missingURL` produces `gly://missing/…`.

### R5: Mechanical renames

| | old | new |
|---|---|---|
| package | `Packages/WorkDashCore` | `Packages/GlyCore` |
| modules | `WorkDashCore`, `WorkDashMCP`, `WorkDashEditor` | `GlyCore`, `GlyMCP`, `GlyEditor` |
| test targets | the same, with `Tests` | the same, with `Tests` |
| app sources | `Apps/Mac` (kept) | targets `gly`, `glyAgent`, `gly-mcp` |
| Xcode | `WorkDash.xcodeproj`, scheme `WorkDash` | `Gly.xcodeproj`, scheme `gly` |
| entitlement files | `WorkDash.entitlements` | `gly.entitlements` |

- **Types with the name in them:** `WorkDashIDs` → `GlyIDs`, `WorkDashTools` → `GlyTools`, `WorkDashMCPServer` → `GlyMCPServer`, `WorkDashApp` → `GlyApp`, `WorkDashAgent` → `glyAgent`.
- **UI strings:**
  - "WorkDash" → "gly" in the menu bar item, Quit/Open menu items, Settings texts, alerts and banners
  - the Data tab's "Erase all WorkDash data?" becomes "Erase all gly data?"
  - quick capture placeholders
- **Scripts and docs:**
  - `scripts/build.sh` (scheme and output `gly.app`)
  - `scripts/manual-checks.py` (the bridge path `gly.app/Contents/MacOS/gly-mcp`; the check tag prefix becomes `gly/checks/…` for new checklists, while existing tasks keep theirs)
  - `docs/*.md` (product name)
- **Specs:** an editorial pass over `openspec/specs/**` replaces the product name in prose. No requirement text changes beyond the name.
- **Unchanged:** `spikes/` (historical), `openspec/changes/archive/**` (history), and the repo folder.

### R6: The user's environment (after the switch, guided)

- **Claude Code MCP config:** the `workdash` server entry in `~/.claude.json`, at command `…/WorkDash.app/Contents/MacOS/wd-mcp`. Claude changes it to `gly` / `…/gly.app/Contents/MacOS/gly-mcp`, only with the user's permission.
- **Joule:** the HTTP endpoint keeps port and token through the settings copy. Only the server name it sees changes.
- **Calendar access:** gly's agent asks again on its first calendar read (new bundle id).
- **Open at login:** re-enable in Settings → Capture if wanted.
- **WorkDash.app:** stop its agent before gly's first start, and delete it from `build/…` after checking gly (R3).

## Risks / Trade-offs

- **[A missed occurrence of "workdash"]** → A final `grep -ri workdash` over `Apps`, `Packages`, `scripts`, `docs` and `project.yml`, expected to find only `GlyIDs.Legacy`, the scheme alias and the migration code. It's part of the tasks.
- **[The takeover runs while WorkDash keeps writing]** → The backup is consistent at its point in time. Writes to WorkDash after that are not carried over, which is why WorkDash's agent is stopped first (R3). Agents still pointed at wd-mcp would write to WorkDash until reconfigured (R6).
- **[Git history across the package rename]** → Done with `git mv`, so file history stays traceable.
- **[A free provisioning team and a new app group]** → `-allowProvisioningUpdates` registers the new group. The first build may need Xcode to refresh the profile; that's a manual check.

## Migration Plan

1. Build gly next to WorkDash.
2. Quit WorkDash and stop its agent (R3).
3. Start gly: the takeover copies the data, and the agent asks for calendar access.
4. Check the data in gly, with the manual checks.
5. Update the Claude Code config (R6).
6. Delete WorkDash.app.

**Rollback:** WorkDash's container is untouched. Starting the old build gets back the state at the moment of the switch.
