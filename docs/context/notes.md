# Stage One — a better Stage Manager with save states (2026-11-05)

Lee's ask: "Extend and have a better stage manager than Apple's one with save states. Same or similar visuals."

Prototype: https://claude.ai/artifact/86coYCHc9oCbEEJRjo2v5E (file: stage-one-prototype.html, images in img/ made with Codex).

## Concept
Free, open source macOS menu-bar app (sibling to Vision One recorder). Keeps Stage Manager's calm look (tilted window groups in a left strip, one group on stage) but adds memory and control.

## Features that beat Stage Manager
1. **Scenes (save states)**: save every group, window, size, position, display and open file. Restore relaunches closed apps. Update a scene when it drifts ("edited" flag).
2. **Rewind**: automatic desk snapshot every 15 min for 7 days; scrub a slider, see a diff (+/−), "Go back to this" or bring back one window.
3. **Layouts per stage**: Free, Halves, Main + side, Thirds, Grid; drag to edge to snap.
4. **Named, unlimited groups**: rename, colour, ⌥1–⌥9, drag a window onto a group or onto "new group".
5. **⌘K command bar**: switch group, restore scene, arrange, find any window.
6. **Rules**: restore a scene when a monitor connects/unplugs, Focus starts, calendar event begins, app opens, Wi-Fi joined, or at a time. 5-second heads-up with Skip.
7. **Meeting mode**: blur Mail, Chat and private windows while screen sharing.
8. **Per-display layouts**: unplug and replug, everything returns.
9. **Share and automate**: export a scene file/link; Shortcuts, CLI (`stage restore "Deep build"`) and an MCP server so AI agents can set up the desk.

## Names
Pick: **Stage One** (fits Version One / Vision One / Lesson One). Others: Wings, Encore, Backstage, Set List. Saved states are called "Scenes". Domains not checked yet.

## Build notes (for later)
Real build would need Accessibility API (AXUIElement) for window move/resize, CGWindowList for snapshots, NSWorkspace for relaunch, ScreenCaptureKit for thumbnails. Apple's own Stage Manager can't be extended via API, so Stage One would replace it (turn Apple's off) rather than plug into it.

## Spotlight + Alfred (2026-11-05, prototype v2)
- **Spotlight**: App Intents (RestoreScene, SaveScene, Rewind, ShowGroup, Arrange) with a SceneEntity, so macOS Spotlight lists actions like "Restore Deep build" and lets you fill in parameters (Tab). Scenes also indexed with Core Spotlight so typing a scene name finds it. Same intents give Shortcuts and Siri for free.
- **Alfred**: a .alfredworkflow with keyword `st`; Script Filter calls the `stage` CLI (`stage list --json`) and returns scenes, groups, layouts, rewind points. `st save <name>`, `st layout halves`, `st rewind`, `st g inbox`. ⌘1–9 picks, ⌘↩ save as, ⌥↩ rewind. Needs Alfred Powerpack (paid by user, not us).
- **Raycast**: same CLI behind a small Raycast extension.
- All three are thin wrappers over one local CLI/URL scheme (`stageone://restore?scene=Deep%20build`), so one engine, three launchers.

## Strip overlap + Dock side fix (2026-11-05, prototype v3)
Lee's pain: Stage Manager's strip overlaps app sidebars/windows on the left, and it can only sit on the side opposite the Dock.
- **Strip on any edge** (left, right, top, bottom), set independently of the Dock. Same edge as the Dock works: the strip sits just inside it.
- **Windows setting**: Never overlap (default; the strip's lane is reserved like the Dock, windows are kept and resized inside the window space, drops get nudged clear), Can overlap (Apple behaviour: strip hides when touched), Auto-hide (strip slides in when the pointer hits that edge).
- **Size**: Previews or Compact icons (72px rail) for more room.
- Changing any of these reflows every window proportionally into the new space; scenes store the space they were saved in, so they reflow on restore too.
- "Show Apple's way" toggle in View demonstrates the old limits side by side.
- Real build: reserve the lane by keeping windows out of it via the Accessibility API (move/resize on window-created/moved events), since macOS has no public API to shrink the usable screen area like the Dock does.
