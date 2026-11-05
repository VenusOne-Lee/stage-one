# Stage One: context pack (2026-11-05)

Stage One is a free, open source macOS window manager. It keeps the calm look of Apple's Stage Manager (window groups in a side strip, one group on stage) and adds what Stage Manager is missing: saved scenes, rewind, layouts, rules, a strip that never overlaps your windows, and launcher support in Spotlight and Alfred.

## Links
- Live prototype: https://claude.ai/artifact/86coYCHc9oCbEEJRjo2v5E (the same file as stage-one-prototype.html in this pack)
- Brainstorm notes: stage-one-notes.md
- Build backlog for Codex/Claude Code: BACKLOG.md (architecture, 61 stories across 14 epics, release plan)
- Sibling project: Vision One, a free open source macOS recorder (same "___ One" family, same licence, same Mac-native stack)

## Suggested project instructions
You're helping Lee build Stage One, a free open source macOS window manager that improves on Apple's Stage Manager. Read README.md first, then BACKLOG.md. Use stage-one-prototype.html as the reference for look, flows and copy.
- **Stack:** native Swift 6 app, SwiftUI with AppKit where needed, for macOS 15 or later. Spotlight actions need macOS 26. MIT licence. Repo suggestion: github.com/VenusOne-Lee/stage-one.
- **Design:**
  - Stage Manager-like, but original. Don't use Apple's assets or the Apple logo.
  - Light mode only. Never green, never dark mode.
  - The accent is stage-light orange (#ef6f2e). The mark is an orange ring with a dot.
  - Bricolage Grotesque for display text, the system font for UI, JetBrains Mono for keys and code.
- **Work style:**
  - Lee prefers visuals over long text.
  - Pick sensible defaults and keep going instead of asking.
- **Images:** Codex image generation runs on Lee's Mac (gpt-5.6-sol model, ~/Pictures/codex-images). Use light, warm scenes with no green.

## Decisions so far
- **Name:** Stage One. Saved states are called **Scenes**.
  - Other name options: Wings, Encore, Backstage, Set List.
  - No domains have been checked yet.
- **Lee's pain points** (these drive the design):
  1. Stage Manager forgets everything on a restart, and there are no save states.
  2. The strip overlaps windows and app sidebars on the left.
  3. The strip can only sit on the side opposite the Dock.
- **What it does better:**
  - **Scenes:** save every group, window, size, position, display and open file. Restoring relaunches closed apps.
  - **Rewind:** an automatic snapshot every 15 minutes for 7 days, with a diff view and "Bring back" for a single window.
  - **Layouts per stage:** Free, Halves, Main + side, Thirds and Grid, plus snapping to the screen edges.
  - **Groups:** unlimited named groups, ⌥1 to ⌥9 shortcuts, and drag a window onto a group to move it.
  - **⌘K command bar.**
  - **Rules:** restore a scene when a monitor connects or unplugs, a Focus starts, a calendar event begins, an app opens, you join a Wi-Fi network, or at a set time. There's a 5-second heads-up with a Skip option.
  - **Meeting mode:** blurs windows marked private (Mail, Chat) while you share your screen.
  - **View menu:**
    - The strip can go on any edge, whatever side the Dock is on. It can share the Dock's edge, sitting just inside it.
    - Windows have three settings: Never overlap (the default), Can overlap (how Apple does it) or Auto-hide.
    - The strip can show previews or compact icons.
    - "Show Apple's way" switches to Apple's rules for comparison.
  - **Launchers:** Spotlight actions through App Intents, which also gives Shortcuts and Siri. An Alfred workflow with the keyword `st`. Raycast later. All of them run on one `stage` command-line tool and a `stageone://` URL scheme.
  - **Automation:** an MCP server (`stage mcp`) so AI agents can set up the desk, and scene export as a small file.
- **Key technical calls:**
  - Apple's Stage Manager can't be extended, so Stage One replaces it, and the user turns Apple's off.
  - Windows of groups that aren't on stage are parked off-screen, the way AeroSpace does it, rather than minimised.
  - Thumbnails come from ScreenCaptureKit.
  - Windows are moved and resized with the Accessibility API (AXUIElement).
  - The reserved strip lane isn't a system feature. Stage One enforces it by moving windows back when they enter the lane.
- **v0.1 (about 6 weeks):**
  - Groups and a strip with live previews, with switching, ⌥1 to ⌥9, and drag to group.
  - The Never overlap lane, with the strip on any edge.
  - Saving and restoring scenes, including relaunching apps.
  - Layouts.
  - The command-line tool, plus a menu bar app.
  - Test with 20 Stage Manager users from X and Reddit.
- **Risks:**
  - Apps that ignore the Accessibility API, or whose windows can't be resized.
  - Fullscreen spaces.
  - Changes in macOS updates.
  - Permissions friction: Accessibility and Screen Recording. Onboarding has to explain these clearly.

## The prototype (stage-one-prototype.html)
- **The desktop:** a fake 1440x900 Mac desktop, scaled to fit the browser.
  - A menu bar with File, Scenes, Rewind, Rules, View and Help, plus Spotlight, Alfred, Meeting mode, the current scene chip and the clock.
  - The strip of groups.
  - The stage, with draggable windows.
  - A layout bar that appears when you hover near the top.
  - The Dock.
- **Panels:**
  - **Scenes:** save, restore, update.
  - **Rewind:** slider, diff, bring back.
  - **Rules:** toggles and a test button.
  - **View:** strip and Dock placement.
  - **Spotlight and Alfred:** mock launch bars.
  - **About:** how Stage One compares with Stage Manager, and the name options.
- **Demo data:** Lee's real projects as window content (Alpaco pitch, Stoepi build, Vision One demo, Lizwi, Lesson One). There are four scenes: Client work, Deep build, Record a demo and Wind down.
- **Images (images/):**
  - wallpaper.jpg, a peach dune wallpaper.
  - Six content photos: mugs, desk, jacaranda, coffee, livingroom and studio.

## Files
- README.md (this file)
- BACKLOG.md
- stage-one-notes.md
- stage-one-prototype.html
- images/
