# Performance budget (SO-130)

Stage One sits in the menu bar all day, so it has to cost close to nothing when idle and
feel instant when switching.

| Metric | Budget | Measured how |
| --- | --- | --- |
| Idle CPU | under 1% averaged over 60s, strip visible, 20+ windows open | `top` / Activity Monitor |
| Group switch | under 300ms for 10 windows, click to last window settled | Instruments, os_signpost / Time Profiler |
| Memory | under 120 MB resident after an hour of use | `footprint`, Activity Monitor "Memory" |
| Identity matching | 200 windows in under 50ms | `PerformanceBudgetTests` (CI) |
| Layout | any layout of 50 windows in under 5ms | `PerformanceBudgetTests` (CI) |

## What keeps idle cost down

- **Event driven inventory.** `WindowInventory` rescans only on AXObserver and NSWorkspace
  events, coalesced to one rescan per 50ms burst.
- **Cheap safety rescan.** The 5s safety timer calls `safetyRescan()`, which hashes the
  layer-0 CGWindowList (ids, owner pids, bounds, on-screen, alpha). It only does the
  Accessibility walk when that hash changed. Most ticks cost one CGWindowList call.
- **Thumbnails only for what's on stage.** Live previews refresh every 2s for on-stage
  windows only; parked windows are captured once as they leave. Refresh stops while Stage
  One is paused, when the displays sleep and when the user session is switched out.
  Without Screen Recording access nothing is captured.
- **Timers carry tolerance** (safety rescan 2s, thumbnails 0.5s) so macOS can coalesce wake-ups.
- **Identity matching** normalises each title once and only scores windows of the same app.

When adding a feature: no polling timers faster than 1s, give every timer a tolerance,
and stop timers in `StageController.stop()`.

## Measuring

Build a release bundle first; debug builds are several times slower.

```sh
ARCHS=arm64 scripts/build-app.sh
open "dist/Stage One.app"
```

### Idle CPU and memory with `top`

```sh
PID=$(pgrep -x StageOne)
top -pid "$PID" -l 60 -s 1 -stats pid,cpu,mem,idlew,power | tail -n 60
footprint "$PID"            # resident and dirty memory, more honest than RSS
```

Leave the Mac alone for the 60 samples. The mean of the `%CPU` column must stay under
1.0 and `MEM` under 120M. `idlew` (idle wake-ups per second) should stay in single digits.

### Switch time with Instruments

1. Open 10 windows across two groups.
2. Instruments > **Time Profiler** (add **os_signpost** and **Animation Hitches**), target `StageOne`.
3. Record, switch between the two groups ten times with the strip or a shortcut, stop.
4. Measure from the click event to the last `AXUIElementSetAttributeValue` of the switch.
   The 0.42s switch animation is excluded from the budget. The budget covers the work
   until every window has its final frame requested; with Reduce Motion on, that is the
   whole switch.

`xctrace` works headless too:

```sh
xcrun xctrace record --template "Time Profiler" --attach "$(pgrep -x StageOne)" --time-limit 30s --output switch.trace
```

### Energy

Activity Monitor > Energy: "Avg Energy Impact" should read 0.0 to 0.5 when idle. Under
`powermetrics --samplers tasks -i 5000` (sudo), Stage One should not appear among the top
wake-up sources.

## Guardrails in CI

`Tests/StageOneCoreTests/PerformanceTests.swift` times identity matching (200 windows) and
layouts (50 windows). It uses the best of five wall-clock runs with generous bounds, so it
fails on algorithmic regressions, not on noisy runners. If one fails, profile before
raising a bound.
