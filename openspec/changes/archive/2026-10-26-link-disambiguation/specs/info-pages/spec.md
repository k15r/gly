# Spec Delta

## ADDED Requirements

### Requirement: Duplicate page titles
Several pages SHALL be allowed to have the same title (for example a "Goals" page per person). Creating or renaming a page to a title that is already used SHALL succeed; the pages are told apart by their tags (see links "Duplicate titles are distinguishable").

#### Scenario: Profile pages per person
- **WHEN** the user creates a page "Profile" tagged `person/alex` and another page "Profile" tagged `person/sam`
- **THEN** both pages exist, and the pages list shows them as "Profile · person/alex" and "Profile · person/sam"
