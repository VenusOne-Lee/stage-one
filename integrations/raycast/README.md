# Stage One for Raycast

Restore scenes, save the desk, arrange the stage and rewind, from Raycast. Every command runs
Stage One's `stage` command, so Stage One must be running.

| Command | Does |
|---|---|
| Restore Scene | Search your scenes and restore one. ⌘S saves the desk as a scene; ⌥↩ rewinds 15 minutes. |
| Save Scene | Save every group and window as a scene. |
| Show Group | Put a group on stage. |
| Arrange Stage | Free, halves, focus, thirds or grid. |
| Rewind Desk | Go back 15 minutes, 1 hour or 3 hours. |

The `stage` command is found at `/usr/local/bin/stage`, `/opt/homebrew/bin/stage`, or inside
`/Applications/Stage One.app`, so installing it on the PATH is optional.

## Develop

```sh
cd integrations/raycast
npm install
npm run dev        # loads the extension into Raycast
npm run typecheck
```

## Publish to the Raycast Store

`author` in `package.json` must be the publisher's Raycast username. Then run `npm run publish`,
which opens a pull request on raycast/extensions for review.
