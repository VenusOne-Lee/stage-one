# Stage One for Alfred

Requires **Alfred's Powerpack** (workflows are a Powerpack feature) and Stage One's `stage`
command (Stage One › Settings › Integrations › Command line › Install).

Install: open `Stage One.alfredworkflow` from the latest release, or use
Stage One › Settings › Integrations › Add to Alfred.

| Type | Does |
|---|---|
| `st <scene>` | Restore a scene. ⌘↩ saves the desk under what you typed; ⌥↩ rewinds 15 minutes. |
| `st save <name>` | Save the desk as a scene. |
| `st layout <kind>` | Arrange the stage: free, halves, focus, thirds, grid. |
| `st rewind` | Go back 15 minutes, 1 hour or 3 hours. |
| `st g <group>` | Put a group on stage. |

The Script Filter (`workflow/filter.js`) calls `stage list --json`; actions run through
`workflow/run.sh`. `scripts/make-alfred.sh` zips the `workflow` folder.
