import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { act } from "./act";
import { plural } from "./stage";
import { useListing } from "./useListing";

export default function ShowGroup() {
  const { data, error, isLoading } = useListing();
  return (
    <List isLoading={isLoading} searchBarPlaceholder="Put a group on stage">
      {error && <List.EmptyView icon={Icon.Warning} title={error} />}
      {data?.groups.map((g) => (
        <List.Item
          key={`${g.index}-${g.name}`}
          title={g.name}
          icon={Icon.AppWindowList}
          subtitle={`Group ${g.index} · ${plural(g.windows, "window")}`}
          accessories={g.active ? [{ tag: "On stage" }] : []}
          actions={
            <ActionPanel>
              <Action
                title="Show Group"
                icon={Icon.ArrowRight}
                onAction={() => act(["group", g.name], `${g.name} is on stage`)}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
