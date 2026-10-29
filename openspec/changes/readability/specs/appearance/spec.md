# Spec Delta

## ADDED Requirements

### Requirement: Readable line length
Text in the editor and in read-only text views SHALL wrap at a comfortable maximum width of about 70 characters at the current text size, centered when the window is wider.

#### Scenario: Wide window
- **WHEN** the user opens a page with long paragraphs in a window much wider than the text
- **THEN** the paragraphs wrap at about 70 characters and the text column is centered

### Requirement: Text size
The user SHALL be able to choose the text size S, M, L or XL in Settings → Appearance, and change it with ⌘+ and ⌘− (⌘0 back to M). The size SHALL apply to notes, the day view and the task and page lists, with titles and chips scaled along, and SHALL be kept across launches.

#### Scenario: Larger text
- **WHEN** the user presses ⌘+ twice from M
- **THEN** notes, the day view and the lists show XL text, and after a restart they still do

#### Scenario: Back to default
- **WHEN** the user presses ⌘0
- **THEN** the text size is M again
