import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { act } from "./act";
import { title } from "./stage";
import { useListing } from "./useListing";

const HINTS: Record<string, string> = {
  free: "Windows stay where you put them",
  halves: "Two windows side by side",
  focus: "One big window, the rest beside it",
  thirds: "Three columns",
  grid: "Every window in a grid",
};

export default function Arrange() {
  const { data, error, isLoading } = useListing();
  return (
    <List isLoading={isLoading} searchBarPlaceholder="Arrange the stage">
      {error && <List.EmptyView icon={Icon.Warning} title={error} />}
      {data?.layouts.map((l) => (
        <List.Item
          key={l}
          title={title(l)}
          icon={Icon.AppWindowGrid2x2}
          subtitle={HINTS[l]}
          actions={
            <ActionPanel>
              <Action
                title="Arrange"
                icon={Icon.ArrowRight}
                onAction={() => act(["layout", l], `Arranged: ${title(l)}`)}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
