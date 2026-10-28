# Manual checks: workweek

Build and run: `scripts/build.sh`, quit gly, restart its agent (Claude does `launchctl kickstart`), `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Uses "Demo: write report" (XL, due Tue 3 Nov) from the future-day-planning demo tasks.

## A. Weekend (tasks 1.1, 2.1)

- [x] A1 Settings → Planning shows a "Days" row with Mon–Fri on and Sat/Sun off; the caption mentions the selected days.
- [x] A2 Go to Saturday and Sunday → the header shows "free 0m"; Friday and Monday show their working time ("Weekend").
- [x] A3 No task shows "start by Sat" or "start by Sun" anywhere in Coming up.
- [x] A4 On Friday's view "Demo: write report" (3 days, due Tuesday) needs work on Friday (e.g. "Fri ≥ 1d"), because only Monday and Tuesday follow.
- [x] A5 Turn Saturday on → Saturday shows its working time and Friday's need for the report drops; turn it off again ("Change working days").
- [x] A6 Try to turn off the last remaining day → it stays on.
