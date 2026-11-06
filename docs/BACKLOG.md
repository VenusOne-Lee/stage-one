# Stage One: product backlog (v1.0, 2026-11-05)

> Stage Manager's calm, with the memory it never had.
> A free, open source macOS window manager.

This backlog is written for an AI coding agent (Codex or Claude Code) and the people reviewing its work.

- Every story has an ID, a priority, a size and acceptance criteria.
- Build in priority order, one story per PR, and keep every PR shippable.
- `stage-one-prototype.html` is the source of truth for look, copy and flows. `README.md` holds the decisions.

---

## 0. How to use this backlog

| Priority | Release | Goal | Target |
|---|---|---|---|
| P0 | v0.1 "Never lose a desk" | Groups, a strip on any edge that never overlaps, scenes, layouts, CLI | 6 weeks |
| P1 | v0.2 "It sets itself up" | Rewind, rules, ⌘K, Spotlight and Alfred, multi-display | +6 weeks |
| P2 | v0.3 "Share and automate" | Meeting mode, scene export, MCP server, Raycast, Shortcuts polish | +6 weeks |
| P3 | Later | Scene marketplace, team sync, iPad Sidecar layouts | — |

Sizes: S = up to 1 day, M = 2 to 3 days, L = about 1 week, XL = split it before starting.

Story format:
```
### SO-123 · Title · P0 · M
Why: the user value.
Acceptance: a testable checklist.
Notes: APIs, edge cases, dependencies.
```

---

## 1. Architecture

- **App:** a Swift 6 menu bar app (LSUIElement) built with SwiftUI and AppKit. The strip, palette and panels are borderless, non-activating NSPanels at a level above normal windows.
- **Targets:** macOS 15 or later. Spotlight App Intents actions need macOS 26, so gate them with `#available`.
- **Window engine (`WindowKit` module):**
  - **Enumerate:** `CGWindowListCopyWindowInfo` to list windows, then match each to an `AXUIElement` by PID and frame.
  - **Track:** `AXObserver` for window created, moved, resized, destroyed, focused and title changed. `NSWorkspace` notifications for app launches and quits.
  - **Move and resize:** `kAXPositionAttribute` and `kAXSizeAttribute`. Every move is checked against the minimum and maximum size the window reports.
  - **Park hidden groups:** windows of groups that aren't on stage move off-screen, 1px visible in a corner (the AeroSpace approach). Don't minimise them, because that's slow and animated.
  - **Thumbnails:** `SCScreenshotManager` (ScreenCaptureKit) captures each window at about 320px wide, every 2 seconds for windows on stage and once when a window is parked.
- **Lane guard:** the strip's reserved lane is kept in a `ScreenLayout` per display. Any window that ends up inside the lane is moved back out, or resized to fit, within 100ms.
- **Store:**
  - Scenes are `~/Library/Application Support/StageOne/Scenes/<slug>.stagescene` files (JSON, versioned).
  - Snapshots go in a SQLite database (GRDB) that keeps 7 days at 15-minute intervals and dedupes identical states.
- **Identity:** a window is matched across launches by bundle ID, title, document URL (`kAXDocumentAttribute`) and the order of its frames. Matching is fuzzy and returns a confidence score.
- **IPC:**
  - The `stage` command-line tool (Swift ArgumentParser) talks to the app over XPC (a Mach service).
  - The `stageone://` URL scheme runs the same commands.
  - App Intents use the same `CommandBus`.
- **Integrations:** App Intents (Spotlight, Shortcuts, Siri, Focus filters), an Alfred workflow (Script Filter calling `stage list --json`), a Raycast extension, and an MCP server over stdio (`stage mcp`).
- **Distribution:** a notarised DMG, a Homebrew cask (`brew install --cask stage-one`), Sparkle updates and the MIT licence.
- **Privacy:** no network calls apart from update checks. Window titles stay on the device.

### Data model (scene file)
```json
{ "version": 1, "name": "Deep build", "savedAt": "2026-11-05T21:40:00+02:00",
  "displays": [{ "id": "LG-27UL850", "frame": [0,0,2560,1440], "strip": "left", "dock": "bottom", "mode": "reserve", "size": "full" }],
  "groups": [{ "name": "Stoepi build", "color": "#ef6f2e", "display": "LG-27UL850", "layout": "focus",
    "windows": [{ "bundleId": "com.microsoft.VSCode", "title": "app.tsx — stoepi", "document": "file:///Users/lee/stoepi/src/app.tsx",
                  "frame": [236,84,700,708], "relaunch": "open -a 'Visual Studio Code' ~/stoepi" }] }],
  "active": 0, "rule": { "type": "displayConnected", "display": "LG-27UL850" }, "options": { "dnd": true, "meetingMode": false } }
```

---

## 2. Design tokens (from the prototype)
- **Colours:** `spot` #ef6f2e (the only accent), `spot-soft` #fde3d2, `ink` #20222b, `ink-2` #585b68, `ink-3` #8b8d98, `focus` #3b63e0, `danger` #e0503d, `amber` #f2b33d. No green anywhere, and light mode only.
- **Glass:** vibrancy panels (`NSVisualEffectView`, material `.popover`), 14 to 16px radius and a soft warm shadow.
- **Type:** Bricolage Grotesque 700 for panel titles, the system font for UI, JetBrains Mono for shortcuts.
- **Strip:**
  - Groups show as stacked previews tilted about 24° in 3D, angled toward the stage. Hovering flattens the tilt to 14° and nudges the group 5px toward the stage.
  - Labels sit under each group with up to two app icons.
- **Motion:**
  - Switching groups: the outgoing windows fly to the strip slot and the incoming ones scale in from 0.55 over 420ms (cubic-bezier .2,.8,.2,1), staggered 45ms each.
  - Layout changes: frames animate over 450ms.
  - Respect Reduce Motion.

---

## 3. Epics and stories

### E1 Onboarding and permissions
### SO-001 · First launch walkthrough · P0 · M
Why: the app is useless without Accessibility and Screen Recording access, so people need to understand why both are needed.
Acceptance:
- [ ] A 3-step sheet covers what Stage One does, Accessibility access and Screen Recording access. Each step has a deep link to the right System Settings pane.
- [ ] Each permission shows a live granted state and updates without a relaunch.
- [ ] The app works without Screen Recording, using app icon tiles instead of previews.
### SO-002 · Turn off Apple's Stage Manager · P0 · S
Acceptance:
- [ ] Detect whether Stage Manager is on (`defaults read com.apple.WindowManager GloballyEnabled`).
- [ ] Offer "Turn it off for me" and "I'll do it", and explain why it has to be off.
- [ ] Turning it off is undoable from Settings.
### SO-003 · Import current windows as groups · P0 · S
Acceptance:
- [ ] On first run, group windows by app, one group per app with a maximum of 8, and name each group after its app.
- [ ] "Start fresh" puts everything in one group instead.
### SO-004 · Menu bar item · P0 · S
Acceptance:
- [ ] The orange ring mark sits in the menu bar.
- [ ] The menu shows the current scene name with an "· edited" flag when the desk has changed.
- [ ] Menu items: Save scene ⌘⇧S, Scenes, Rewind, View, Rules, Settings, Pause Stage One, Quit.

### E2 Window engine
### SO-010 · Window inventory · P0 · L
Acceptance:
- [ ] Live list of standard windows with PID, bundle ID, title, frame, display and document.
- [ ] Ignores panels, sheets, the menu bar, desktop widgets and our own windows.
- [ ] Handles 200 or more windows with less than 2% CPU at idle.
### SO-011 · Move and resize with constraints · P0 · M
Acceptance:
- [ ] `WindowKit.setFrame(id, rect, animated)` respects each window's minimum and maximum size and reports the frame it actually got.
- [ ] Animation is an interpolated sequence of setFrame calls at 60fps, falling back to a jump for apps that respond slowly.
### SO-012 · Park and unpark windows · P0 · M
Acceptance:
- [ ] Parked windows move off-screen and unparking restores their exact frame.
- [ ] Parking survives an app relaunch through identity matching (SO-013).
- [ ] Parked windows never appear in the stage area or in screenshots of the stage.
### SO-013 · Window identity matching · P0 · L
Acceptance:
- [ ] Windows are matched by bundle ID, document, title similarity and order.
- [ ] Each match gets a confidence score from 0 to 1. Below 0.6, the window goes to an "Unmatched" tray instead of being guessed.
- [ ] Unit tests cover renamed tabs, multiple Finder windows and Chrome profiles.
### SO-014 · Fullscreen and Spaces · P1 · M
Acceptance:
- [ ] Native fullscreen windows are left alone and shown in the strip with a "Full screen" badge.
- [ ] Each Space has its own groups, or one shared set, depending on a setting.
### SO-015 · Uncooperative apps list · P1 · S
Acceptance:
- [ ] Apps that ignore Accessibility moves (tested list: some Electron apps, games) are flagged.
- [ ] Flagged apps can float above the stage, and users can add their own exceptions.

### E3 Groups and the strip
### SO-020 · Strip panel with live previews · P0 · L
Acceptance:
- [ ] Each group shows a stack of up to 3 window thumbnails, its label and app icons, tilted as in the prototype.
- [ ] Clicking a group swaps it onto the stage using the switch motion.
- [ ] The active group isn't shown in the strip, which matches Stage Manager.
### SO-021 · Keyboard switching ⌥1 to ⌥9 · P0 · S
Acceptance:
- [ ] Global hotkeys, which can be changed in Settings.
- [ ] Holding ⌥ shows the number badges on the strip.
### SO-022 · Drag a window onto a group · P0 · M
Acceptance:
- [ ] Dragging a window's title bar over a strip group highlights it with a dashed orange outline. Dropping moves the window into that group.
- [ ] Dropping on "+ New group" creates a group named after the window.
- [ ] Undo is offered in a toast.
### SO-023 · Rename, colour and reorder groups · P0 · S
Acceptance:
- [ ] Double-click a label to rename it inline.
- [ ] Right-click for colour, Close group and Move to display.
- [ ] Drag groups to reorder them.
### SO-024 · Unlimited groups with scrolling · P1 · S
Acceptance:
- [ ] The strip scrolls past the visible slots, with a small search field once there are more than 8 groups.
### SO-025 · Option-click to add to the stage · P1 · S
Acceptance:
- [ ] ⌥-click a group to add its windows to the current stage instead of swapping, which matches Stage Manager's shift-click.

### E4 Strip and Dock placement (Lee's pain points 2 and 3)
### SO-030 · Strip on any edge · P0 · M
Acceptance:
- [ ] The strip can sit left, right, top or bottom on each display, whatever side the Dock is on.
- [ ] On the Dock's edge, the strip sits just inside the Dock, and the gap updates when the Dock auto-hides or changes size (read from `com.apple.dock` and the visible frame).
- [ ] On the top or bottom edge, groups lay out in a row.
### SO-031 · Never overlap lane (default) · P0 · L
Acceptance:
- [ ] The stage's usable area is the display's visible frame minus the strip's lane.
- [ ] Any window that moves, resizes or opens inside the lane is moved out, or shrunk to fit, within 100ms. It's animated unless the user is mid-drag, in which case it's corrected on mouse-up.
- [ ] Zooming (double-clicking the title bar) and the green-button tile fill the usable area, not the full screen.
- [ ] App sidebars, such as Finder, Mail and Slack, are never covered by the strip.
### SO-032 · Can overlap mode (Apple's way) · P1 · S
Acceptance:
- [ ] When a window touches the lane, the strip hides by sliding 40px off and fading. Moving to that edge brings it back.
### SO-033 · Auto-hide mode · P1 · S
Acceptance:
- [ ] The strip stays hidden until the pointer is within 4px of its edge, then slides in over the windows. It hides again 600ms after the pointer leaves.
### SO-034 · Compact icon rail · P1 · M
Acceptance:
- [ ] A rail about 72px wide with one tile per group showing up to two app icons and a ⌥ number badge. Hovering a tile shows a preview popover.
### SO-035 · Reflow on placement change · P0 · M
Acceptance:
- [ ] Changing the strip edge, Dock side, mode or size remaps every window's frame proportionally from the old usable area to the new one, then clamps it.
- [ ] Scenes store the usable area they were saved in and are reflowed the same way on restore.
### SO-036 · View popover with schematic · P1 · S
Acceptance:
- [ ] Matches the prototype: segmented controls, a mini schematic (strip, Dock, window space), a note, and Apple's way / Stage One way presets.

### E5 Layouts
### SO-040 · Per-stage layouts · P0 · M
Acceptance:
- [ ] Free, Halves, Main + side, Thirds and Grid with an 8px gap inside the usable area.
- [ ] Each group remembers its layout.
- [ ] The layout bar appears when the pointer reaches the top of the stage area.
### SO-041 · Edge snapping · P0 · S
Acceptance:
- [ ] Dragging to the left or right edge of the usable area shows an orange ghost and snaps to that half. The top edge fills the area.
### SO-042 · Keyboard layouts · P1 · S
Acceptance:
- [ ] Shortcuts ⌃⌥← → ↑ for halves and fill, and ⌃⌥G for grid, all customisable.
### SO-043 · New windows follow the layout · P1 · M
Acceptance:
- [ ] A new window on a stage that has a layout slots into it. Free stages cascade new windows instead.

### E6 Scenes (save states)
### SO-050 · Save the desk as a scene · P0 · M
Acceptance:
- [ ] ⌘⇧S opens the Save box with name, trigger and options.
- [ ] Saving writes a `.stagescene` file covering every display, group, window, frame, document, active group and strip settings.
- [ ] The toast reads "Saved “<name>”: N groups, M windows".
### SO-051 · Restore a scene · P0 · L
Acceptance:
- [ ] Matches existing windows by identity, moves them into their groups and frames, and parks windows that aren't in the scene into an "Other" group. Nothing is closed.
- [ ] Restoring is undoable for 30 seconds.
### SO-052 · Relaunch closed apps and documents · P0 · M
Acceptance:
- [ ] Missing windows are relaunched by opening the document URL with its app, or by launching the app. Restore waits up to 10 seconds per app, then places the window.
- [ ] A progress chip shows "Opening 3 apps…".
### SO-053 · Edited state and update · P0 · S
Acceptance:
- [ ] When the desk differs from the current scene, the menu bar and the scene card show "· edited", and the card offers "Update".
### SO-054 · Scenes panel · P0 · M
Acceptance:
- [ ] Glass panel with the save box on top and scene cards below. Each card has a mini desk preview, name, groups and windows count, saved time, trigger chips, and Restore, or an "On stage" badge.
### SO-055 · Scene options · P1 · S
Acceptance:
- [ ] Per-scene options: Do Not Disturb, Meeting mode, hide apps not in the scene, close apps not in the scene (asks first), and a wallpaper.
### SO-056 · Multi-display scenes · P1 · L
Acceptance:
- [ ] Displays are identified by vendor, model and serial number. Scenes saved with two displays restore onto one display by folding groups and keeping their sizes, with a toast explaining what happened.

### E7 Rewind
### SO-060 · Automatic snapshots · P1 · M
Acceptance:
- [ ] A snapshot every 15 minutes, plus on sleep, display change and quit. Identical states are skipped and snapshots are kept for 7 days. The database stays under 20 MB.
### SO-061 · Rewind panel · P1 · M
Acceptance:
- [ ] A slider with time ticks, a mini desk preview, and a "Since then" diff (+ new windows, − gone).
- [ ] "Go back to this" restores the snapshot like a scene.
### SO-062 · Bring back one window · P1 · S
Acceptance:
- [ ] Lists windows that existed then but are gone now. "Bring back" reopens a window and puts it in its old group.

### E8 Rules
### SO-070 · Rule engine · P1 · M
Acceptance:
- [ ] Triggers: display connected or disconnected, Focus started, calendar event started, app launched, Wi-Fi network joined, and time of day.
- [ ] Every rule run shows a 5-second toast with a Skip button.
- [ ] Rules can be turned on and off individually, and there's a log of the last 50 runs.
### SO-071 · Display rules · P1 · S
Acceptance:
- [ ] Uses `CGDisplayRegisterReconfigurationCallback`. Unplugging folds all groups onto the remaining screen.
### SO-072 · Focus filter · P1 · M
Acceptance:
- [ ] A `SetFocusFilterIntent` lets a Focus mode choose a scene.
### SO-073 · Calendar rules · P2 · M
Acceptance:
- [x] Uses EventKit, with permission asked only when this rule is first made. Rules match an event title keyword or a calendar.
### SO-074 · Wi-Fi rules · P2 · S
Acceptance:
- [x] Uses CoreWLAN for the network name. Explains that macOS needs Location access to read it.

### E9 Command bar
### SO-080 · ⌘K palette · P1 · M
Acceptance:
- [ ] Fuzzy search across groups, scenes, layouts, rewind points, rules and every window title.
- [ ] Arrow keys and Enter work. Results show their type and shortcut.
- [ ] The hotkey can be changed, because ⌘K clashes with some apps (the default could be ⌃Space).

### E10 Launchers: Spotlight and Alfred
### SO-090 · App Intents and entities · P1 · M
Acceptance:
- [ ] Intents: `RestoreScene(scene)`, `SaveScene(name)`, `RewindTo(time)`, `ShowGroup(group)`, `Arrange(layout)`, `ToggleMeetingMode`.
- [ ] `SceneEntity` and `GroupEntity` come with queries.
- [ ] App Shortcuts include phrases.
### SO-091 · Spotlight actions · P1 · S
Acceptance:
- [ ] On macOS 26, typing "deep" in Spotlight shows "Restore Deep build", and pressing Tab fills in parameters.
- [ ] Scenes are indexed with Core Spotlight so a scene can be found by name.
### SO-092 · Alfred workflow · P1 · M
Acceptance:
- [ ] Ships as a `.alfredworkflow` file.
- [ ] Keyword `st` uses a Script Filter calling `stage list --json`.
- [ ] Subcommands: `st <scene>`, `st save <name>`, `st layout <kind>`, `st rewind`, `st g <group>`.
- [ ] Modifiers: ⌘↩ save as, ⌥↩ rewind.
- [ ] README notes that Alfred's Powerpack is required.
### SO-093 · Raycast extension · P2 · M
Acceptance:
- [x] The same commands through the CLI, published to the Raycast store.

### E11 CLI and URL scheme
### SO-100 · `stage` CLI · P0 · M
Acceptance:
- [ ] Commands: `stage list [--json]`, `stage restore <scene>`, `stage save <name>`, `stage group <name|index>`, `stage layout <kind>`, `stage rewind [--to <time>]`, `stage export <scene> <file>`, `stage import <file>`.
- [ ] Installed to `/usr/local/bin` from Settings, or by Homebrew.
### SO-101 · `stageone://` URL scheme · P1 · S
Acceptance:
- [ ] `stageone://restore?scene=Deep%20build` and the equivalent for every command, with a confirmation prompt for destructive ones.

### E12 Meeting mode and privacy
### SO-110 · Meeting mode · P2 · M
Acceptance:
- [x] Turns on by hand, by a rule, or automatically when screen sharing starts (detected by `SCShareableContent` / a CGSession check).
- [x] Windows of apps marked private (Mail, Messages, Slack, WhatsApp by default) get a blurred overlay panel reading "Hidden while you share".
- [x] The strip hides their thumbnails.
### SO-111 · Private window picker · P2 · S
Acceptance:
- [x] Mark an app, or a single window by title pattern, as private.

### E13 Share and automate
### SO-120 · Export and import scenes · P2 · S
Acceptance:
- [x] A scene exports as a `.stagescene` file without document paths unless the user ticks "Include files".
- [x] Double-clicking a scene file imports it.
### SO-121 · MCP server · P2 · M
Acceptance:
- [x] `stage mcp` runs over stdio with these tools: `list_scenes`, `restore_scene`, `save_scene`, `list_groups`, `arrange`, `rewind_points`.
- [x] Every tool that changes the desk asks for confirmation in a Stage One toast unless "Allow without asking" is set for that tool.
### SO-122 · Shortcuts actions polish · P2 · S
Acceptance:
- [ ] Every intent has a parameter summary, and output types can be chained.

### E14 Quality, release and growth
### SO-130 · Performance budget · P0 · S
Acceptance:
- [ ] Idle CPU under 1%. A group switch completes in under 300ms for 10 windows. Memory under 120 MB.
### SO-131 · Crash-safe state · P0 · S
Acceptance:
- [ ] If Stage One quits or crashes, every parked window is unparked to its last frame, using a watchdog helper and a signal handler.
### SO-132 · Settings window · P0 · M
Acceptance:
- [ ] Tabs: General, Strip & Dock, Shortcuts, Rules, Privacy, Integrations, About.
### SO-133 · Release pipeline · P0 · M
Acceptance:
- [ ] GitHub Actions: build, test, sign, notarise and staple the DMG, publish a Sparkle appcast and bump the Homebrew cask.
### SO-134 · Landing page · P1 · M
Acceptance:
- [ ] A one-page site with a looping demo video recorded with Vision One, a Stage Manager comparison table, a download button and a GitHub link.
### SO-135 · Telemetry-free feedback · P1 · S
Acceptance:
- [ ] Help > Send feedback opens a pre-filled GitHub issue with macOS version and app list (with consent). There are no analytics.

---

## 4. v0.1 test plan
- Recruit 20 Stage Manager users who complain about it online (r/MacOS, X).
- Tasks:
  1. Set up groups.
  2. Save "Work".
  3. Restart the Mac.
  4. Restore it.
  5. Move the strip to the Dock's side.
  6. Open Finder and check its sidebar isn't covered.
- Success means 80% complete all tasks without help, and 60% still use it after 2 weeks.
