# Spec Delta

## ADDED Requirements

### Requirement: Tag picker
Tags SHALL be added to a task or page through an "Add tag" menu that mirrors the tag hierarchy with submenus (for example project ▸ atlas). A group node that is also a tag SHALL be selectable itself. Each group SHALL offer "New tag in <group>/…" with the group prefilled, and the top level SHALL offer "New tag…". Tags already on the item SHALL not be offered again. New tag names SHALL follow the tag name rules.

#### Scenario: Pick a nested tag
- **WHEN** tags `project/atlas` and `project/beta` exist and the user opens "Add tag" on a task and chooses project ▸ atlas
- **THEN** the task gets the tag `project/atlas`

#### Scenario: New tag in a group
- **WHEN** the user chooses project ▸ "New tag in project/…" and enters `gamma`
- **THEN** the task gets the new tag `project/gamma`

#### Scenario: Invalid new tag
- **WHEN** the user enters `a//b` as a new tag
- **THEN** the tag is not added and the field says that segments must not be empty

## REMOVED Requirements

### Requirement: Tag autocomplete
**Reason**: Replaced by the hierarchical tag picker (user request during planning-day-view): choosing from a menu is faster and shows the existing structure.
**Migration**: Use "Add tag" and its submenus; new tags via "New tag…" (prefilled with the group).
