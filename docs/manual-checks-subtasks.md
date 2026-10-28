# Manual checks: subtasks

Build and run: `scripts/build.sh`, quit gly, `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: "Demo: plan offsite" (effort XL, due Fri 6 Nov, tag `gly/checks/subtasks/demo`) exists without notes.

## A. Checklist parts (task 2.1)

- [ ] A1 In "Demo: plan offsite", write the notes `- [ ] Outline (S)`, `- [ ] Draft (1d)`, `- [ ] Review (90m)` → its rows show "0/3", and the Progress row reads "1d 3h 30m left from 0/3 parts" ("Break a task down").
- [ ] A2 Add `- [ ] Book room` → "0/4", and the Progress row says "1 without estimate" ("Item without estimate").
- [ ] A3 Tick off "Outline" (click its box in the read view) → "1/4" and "1d 1h 30m left"; the day view plans with that ("Ticking off a part").
- [ ] A4 For this task "Set remaining…", "Reset" and "done for today" aren't offered.
- [ ] A5 Tick off the rest → "All parts done" with "Complete task"; the task stays open until you click it ("Last part ticked off").
- [ ] A6 A checklist inside a code block (```) doesn't count; `- [ ] Call (maybe)` keeps "(maybe)" in its title.
- [ ] A7 A task with effort L and checklist items without estimates still offers "Set remaining…" and "done for today" ("Unestimated parts").

## B. Agents (task 3.1)

- [ ] B1 Claude creates a task over MCP with three checklist items in its notes, two estimated → gly shows "0/3" and the sum of the two as what's left ("Agent breaks a task down").
- [ ] B2 Claude ticks one item off by changing the notes → gly shows it done ("Agent ticks off a part").
