# Proposal

## Why

Planning treats every day as a working day: Saturday and Sunday each add a full working day of free time. So gly says "start by Sun", plans work for the weekend, and thinks a 3-day task due Tuesday needs nothing on Friday. Planning needs to know which days are working days.

## What Changes

- **Working days:** a configurable set of weekdays (default Monday–Friday) in Settings → Planning, next to the working hours.
- **Non-working days have no free time:** nothing is counted there, so the work needed, "can't fit", "start by", the day header and capacity bar, the snooze warning and the agents' planning data all skip them. "Start by" never lands on a non-working day.
- A working day keeps the same hours as before; effort sizes stay defined in working days.

Out of scope: holidays and other one-off days off, different hours per weekday.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `daily-planning`: working hours apply on the configured working days only; other days have no free time.

## Impact

- `GlyCore`: `WorkingHours` gains the working weekdays; its window is empty on other days, which `FreeTime` and everything built on it follow. `SharedSettings` stores them (`workingDays`), shared with the agent.
- `Apps/Mac/App/PlanningSettingsView.swift`: weekday toggles.
- No schema change, no MCP tool change (the agent reads the shared setting).
