# Spec Delta

## ADDED Requirements

### Requirement: Tag color on the tag page
The tag page SHALL show the tag's effective color next to its name and offer the same color menu as the tag list (palette and "Automatic"), indicating whether the color is the tag's own, inherited from a tag above, or automatic.

#### Scenario: Inherited color shown
- **WHEN** `person` is green and the user opens the tag page of `person/alex`, which has no own color
- **THEN** the header shows green, marked as inherited from `person`, and choosing orange in its color menu makes `person/alex` orange
