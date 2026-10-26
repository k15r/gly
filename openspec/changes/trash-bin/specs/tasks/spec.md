# Spec Delta

## MODIFIED Requirements

### Requirement: Delete a task
The system SHALL let the user delete a task. A deleted task SHALL disappear from all views but SHALL remain recoverable through undo and from the Trash.

#### Scenario: Delete and undo
- **WHEN** the user deletes a task and then chooses Undo
- **THEN** the task returns with all its fields and tags

#### Scenario: Delete and restore later
- **WHEN** the user deletes a task, makes other changes, and later restores the task from the Trash
- **THEN** the task returns with all its fields and tags, and the other changes stay
