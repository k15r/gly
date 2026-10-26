# Spec Delta

## MODIFIED Requirements

### Requirement: Deleted link targets
A link whose target was deleted SHALL stay in the text and be shown as "link target deleted". Clicking it (⌘-click while editing) SHALL open a menu offering to restore the target (with when and by whom it was deleted), to link to a live item of the same kind and title instead, and to show the target in the Trash. If the target is restored, the link SHALL work again.

#### Scenario: Linked task deleted
- **WHEN** a page links to a task and the task is deleted
- **THEN** the page shows the link as "link target deleted"

#### Scenario: Restore from a broken link
- **WHEN** the user clicks a link to the deleted page "Goals" and chooses "Restore “Goals”"
- **THEN** the page is restored, and this link and every other link to it work again

#### Scenario: Link to the surviving duplicate
- **WHEN** of two pages "Goals" the one tagged `person/bob` was deleted, and the user clicks a link to it and chooses "Link to “Goals · person/alex” instead"
- **THEN** this link points to the page tagged `person/alex`, the deleted page stays in the Trash, and one Undo brings the old link back
