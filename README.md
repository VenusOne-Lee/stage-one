# Stage One

> Stage Manager's calm, with the memory it never had.

A free, open source macOS window manager. Window groups live in a side strip and one group is on stage, like Apple's Stage Manager, plus what it's missing: saved **Scenes**, Rewind, layouts, rules, a strip on any edge that never overlaps your windows, and a `stage` CLI.

- Decisions and context: [docs/context/README.md](docs/context/README.md)
- Backlog: [docs/BACKLOG.md](docs/BACKLOG.md)
- Prototype (look, copy and flows): [docs/context/prototype.html](docs/context/prototype.html)

MIT licensed.

## First launch

Builds that aren't notarised by Apple (every CI build, and releases made without the signing secrets in [docs/RELEASING.md](docs/RELEASING.md)) are ad-hoc signed, so macOS 15 stops the first launch with **"Stage One.app" Not Opened** and only a Done button. That's Gatekeeper, not a broken download. To open it once:

1. Drag Stage One to Applications and try to open it. Press **Done**.
2. Open **System Settings › Privacy & Security**, scroll to Security, and press **Open Anyway** next to "Stage One.app was blocked". Confirm with your password.

Or in Terminal: `xattr -dr com.apple.quarantine "/Applications/Stage One.app"`, then open it as usual. macOS remembers the choice, and updates install without asking again.

## Meeting mode

⌃⌥M, the menu bar or the command bar turns it on, and by default it turns itself on while you share your screen (macOS Screen Sharing, Zoom, Teams, Meet in the browser). Windows of private apps (Mail, Messages, Slack and WhatsApp to start with; change them in Settings › Privacy) get a frosted cover reading "Hidden while you share", and the strip hides their previews. A scene can turn it on too.

## AI assistants (MCP)

`stage mcp` is a Model Context Protocol server over stdio with `list_scenes`, `restore_scene`, `save_scene`, `list_groups`, `arrange` and `rewind_points`. Add it to your client:

```json
{ "mcpServers": { "stage-one": { "command": "/usr/local/bin/stage", "args": ["mcp"] } } }
```

`restore_scene` and `arrange` move windows, so Stage One asks in a toast first (ignore it to say no) unless you allow them in Settings › Integrations.

## Launchers

- **Alfred:** `Stage One.alfredworkflow` comes with each release and in Settings › Integrations › Add to Alfred. Keyword `st`: `st <scene>` restores (⌘↩ saves the desk under what you typed, ⌥↩ rewinds 15 minutes), `st save <name>`, `st layout <kind>`, `st rewind`, `st g <group>`. It needs Alfred's Powerpack and the `stage` command (Settings › Integrations › Command line). See [integrations/alfred](integrations/alfred/README.md).
- **Raycast:** Restore Scene, Save Scene, Show Group, Arrange Stage and Rewind Desk. Source in [integrations/raycast](integrations/raycast/README.md), headed for the Raycast Store.
- **Spotlight and Shortcuts:** scenes are indexed in Spotlight. The Shortcuts app has Restore Scene, Save Scene, Rewind Desk, Show Group, Arrange Stage and Set Meeting Mode, plus Get Scenes, Get Current Scene, Get Groups and Get Rewind Points. Actions return the scene, group, time or on/off they acted on, and scenes and groups expose their name, window count and more, so actions chain.
