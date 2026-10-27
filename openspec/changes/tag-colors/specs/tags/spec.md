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
