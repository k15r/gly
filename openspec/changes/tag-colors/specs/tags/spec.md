# Spec Delta

## ADDED Requirements

### Requirement: Tag colors
Every tag SHALL have an effective color: its own color if set, else the nearest color set on a tag above it, else a color derived from its top-level name. Own colors SHALL come from a fixed palette readable in light and dark mode. Tag chips SHALL use the effective color everywhere, and tag rows in the tag list SHALL show it as a dot.

#### Scenario: Color a group
- **WHEN** `person` is set to green, and tags `person/alex` and `person/alex/blargh` exist without own colors
- **THEN** chips and dots of `person`, `person/alex` and `person/alex/blargh` are green everywhere

#### Scenario: Override below
- **WHEN** `person` is green and `person/alex` is set to orange
- **THEN** `person/alex` and `person/alex/blargh` are orange, and `person/sam` stays green

#### Scenario: No colors set
- **WHEN** no tag above `project/atlas` has a color
- **THEN** its chip uses the color derived from `project`, the same for every `project/…` tag

### Requirement: Set a tag color in the tag list
The tag list's context menu on a tag SHALL offer the palette colors and "Automatic" (no own color, so the tag inherits again), with the current choice marked. This SHALL work for group names without their own tag too. Each change SHALL be one undo step.

#### Scenario: Back to automatic
- **WHEN** `person` is green, `person/alex` is orange, and the user chooses "Automatic" for `person/alex`
- **THEN** `person/alex` and its subtags are green again, and one Undo brings orange back

### Requirement: Show unused tags
The tag list SHALL offer a "Show unused tags" toggle. When it is on, tags used only by finished tasks SHALL be listed too, marked as unused, so they can be colored, renamed or deleted. The choice SHALL be remembered.

#### Scenario: Tag of finished work
- **WHEN** `person/old` is assigned only to a done task and the user turns on "Show unused tags"
- **THEN** `old` appears below `person`, marked as unused, and its context menu offers color, rename and delete

### Requirement: Rename a tag
The user SHALL be able to rename a tag from the tag list's context menu and from its tag page. Subtags SHALL be renamed along, items keep their tags under the new name, and links to the tag SHALL keep working and show the new name. A rename SHALL be one undo step.

#### Scenario: Rename a group
- **WHEN** the user renames `person` to `people`, and `person/alex` and `person/sam` exist
- **THEN** the tags are `people`, `people/alex` and `people/sam` with all their items, and a link to `person/alex` now reads `people/alex`

#### Scenario: Fix a typo
- **WHEN** the user renames `projct/atlas` to `project/atlas` and no tag of that name exists
- **THEN** every item tagged `projct/atlas` is now tagged `project/atlas`, and one Undo brings the old name back

### Requirement: Merge tags on rename
Renaming a tag to a name that already exists SHALL ask for confirmation and then merge: the items of both SHALL carry the existing tag, the descriptions SHALL be joined, links to the renamed tag SHALL point to the existing one, and subtags SHALL be merged the same way. A merge SHALL be one undo step.

#### Scenario: Merge two spellings
- **WHEN** `person/al` (two tasks) is renamed to the existing `person/alex` (one page) and the user confirms
- **THEN** the two tasks and the page are tagged `person/alex`, `person/al` is gone, and links to `person/al` open `person/alex`

#### Scenario: Merge declined
- **WHEN** the user renames `person/al` to the existing `person/alex` and cancels the confirmation
- **THEN** nothing changes

### Requirement: Delete a tag
The user SHALL be able to delete a tag from the tag list's context menu and from its tag page, after a confirmation that says how many items carry it. The items SHALL lose that tag, subtags SHALL stay, and links to the deleted tag SHALL be shown as "link target deleted". A delete SHALL be one undo step.

#### Scenario: Delete a used tag
- **WHEN** the user deletes `project/old`, which three tasks carry, and confirms "Remove from 3 items"
- **THEN** the three tasks no longer carry `project/old`, the tag disappears from the tag list, and one Undo brings it back on all three
