# Spec Delta

## ADDED Requirements

### Requirement: Tag color on the tag page
The tag page SHALL show the tag's name in its effective color, with a small color swatch next to it that opens the same color menu as the tag list and whose tooltip says whether the color is the tag's own, inherited from a tag above, or automatic.

#### Scenario: Inherited color shown
- **WHEN** `person` is green and the user opens the tag page of `person/alex`, which has no own color
- **THEN** the name is green, the swatch's tooltip says "inherited from person", and choosing orange in its menu makes `person/alex` orange

### Requirement: Manage a tag from its tag page
The tag page SHALL offer to rename the tag and to delete it, with the same behavior as in the tag list (subtags renamed along, merge after confirmation on an existing name, delete after confirmation). After a rename or merge, the tag page SHALL show the tag under its new name; after a delete it SHALL close.

#### Scenario: Rename from the tag page
- **WHEN** the user renames `projct` to `project` on its tag page
- **THEN** the tag page now shows `project` with the same items and description
