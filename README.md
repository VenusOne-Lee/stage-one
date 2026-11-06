# Stage One

> Stage Manager's calm, with the memory it never had.

A free, open source macOS window manager. Window groups live in a side strip and one group is on stage, like Apple's Stage Manager, plus what it's missing: saved **Scenes**, Rewind, layouts, rules, a strip on any edge that never overlaps your windows, and a `stage` CLI.

- Decisions and context: [docs/context/README.md](docs/context/README.md)
- Backlog: [docs/BACKLOG.md](docs/BACKLOG.md)
- Prototype (look, copy and flows): [docs/context/prototype.html](docs/context/prototype.html)

MIT licensed.

## Launchers

- **Alfred:** `Stage One.alfredworkflow` comes with each release and in Settings › Integrations › Add to Alfred. Keyword `st`: `st <scene>` restores (⌘↩ saves the desk under what you typed, ⌥↩ rewinds 15 minutes), `st save <name>`, `st layout <kind>`, `st rewind`, `st g <group>`. It needs Alfred's Powerpack and the `stage` command (Settings › Integrations › Command line). See [integrations/alfred](integrations/alfred/README.md).
- **Spotlight and Shortcuts:** scenes are indexed in Spotlight, and Restore Scene, Save Scene, Rewind Desk, Show Group and Arrange Stage are in the Shortcuts app.
