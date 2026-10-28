# Tasks

## 1. Core

- [x] 1.1 Working days (W1–W3): `WorkingHours.workdays` (default Mon–Fri) with an empty window on other days; `SharedSettings` stores `workingDays`; verify with tests for "Weekend" (start by Fri for a task due Monday that's fully booked, 0 free minutes on Saturday and Sunday), "Change working days" (Saturday counted once added), free time across a weekend, the snooze fit check skipping the weekend, and settings round-trip incl. the Mon–Fri default

## 2. App

- [x] 2.1 Settings → Planning weekday toggles (W4) in locale order, at least one day kept, caption updated; verify with a clean build and manually: change the days, see free time and "start by" follow, Saturday/Sunday views show "free 0m"

## Workflow follow-up

- Run `/opsx:verify workweek`, then archive; then resume the checks of `future-day-planning`.
