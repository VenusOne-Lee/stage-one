# Stage One: notes for coding agents

- Read docs/context/README.md (decisions) and docs/BACKLOG.md (stories). docs/context/prototype.html is the source of truth for look, copy and flows.
- One backlog story per PR, in priority order. Title PRs `SO-xxx: <story title>`.
- Design: light mode only, never green, never dark mode. Accent #ef6f2e. Use `Theme` tokens in Sources/StageOneApp/Theme.swift. No Apple assets.
- Layout: `StageOneCore` is pure Swift (no AppKit) and holds anything testable: geometry, layouts, scenes, identity, commands. Put logic there and unit-test it in Tests/StageOneCoreTests. `WindowKit` wraps CGWindowList, AXUIElement and ScreenCaptureKit. `StageOneApp` is the LSUIElement menu bar app. `stage` is the CLI.
- Coordinates: everything uses the top-left global space of the Accessibility API. Convert NSScreen frames with `CoordinateSpace.flip`.
- Swift 6 language mode. UI and WindowKit types are `@MainActor`.
- Build: `swift build && swift test`. Bundle: `scripts/build-app.sh` (macOS only). CI on macos-15 builds every PR and uploads the DMG.
