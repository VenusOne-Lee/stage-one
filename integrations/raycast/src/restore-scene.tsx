import { Action, ActionPanel, Icon, List, useNavigation } from "@raycast/api";
import { useState } from "react";
import { act } from "./act";
import { plural } from "./stage";
import { useListing } from "./useListing";
import SaveScene from "./save-scene";

export default function RestoreScene() {
  const { data, error, isLoading } = useListing();
  const [query, setQuery] = useState("");
  const { push } = useNavigation();
  return (
    <List isLoading={isLoading} searchBarPlaceholder="Restore a scene" onSearchTextChange={setQuery}>
      {error ? (
        <List.EmptyView icon={Icon.Warning} title={error} />
      ) : (
        <List.EmptyView
          icon={Icon.AppWindowGrid3x3}
          title={query ? `No scene matches “${query}”` : "No scenes yet"}
          description="⌘S saves the desk as a scene"
          actions={
            <ActionPanel>
              <Action
                title="Save Desk as Scene"
                icon={Icon.SaveDocument}
                onAction={() => push(<SaveScene name={query} />)}
              />
            </ActionPanel>
          }
        />
      )}
      {data?.scenes.map((s) => (
        <List.Item
          key={s.name}
          title={s.name}
          icon={Icon.AppWindowGrid3x3}
          subtitle={`${plural(s.windows, "window")} in ${plural(s.groups, "group")}`}
          accessories={s.current ? [{ tag: "Current" }] : []}
          actions={
            <ActionPanel>
              <Action
                title="Restore Scene"
                icon={Icon.ArrowRight}
                onAction={() => act(["restore", s.name], `Restored “${s.name}”`)}
              />
              <Action
                title="Save Desk as Scene"
                icon={Icon.SaveDocument}
                shortcut={{ modifiers: ["cmd"], key: "s" }}
                onAction={() => push(<SaveScene name={query} />)}
              />
              <Action
                title="Rewind 15 Minutes"
                icon={Icon.RotateAntiClockwise}
                shortcut={{ modifiers: ["opt"], key: "return" }}
                onAction={() => act(["rewind", "--to", "15m"], "Rewound 15 minutes")}
              />
              <Action.CopyToClipboard title="Copy Restore Command" content={`stage restore "${s.name}"`} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
