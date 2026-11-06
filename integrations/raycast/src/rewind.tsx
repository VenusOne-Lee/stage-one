import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { act } from "./act";

const POINTS: [string, string][] = [
  ["15m", "15 minutes"],
  ["60m", "1 hour"],
  ["180m", "3 hours"],
];

export default function Rewind() {
  return (
    <List searchBarPlaceholder="Rewind the desk">
      {POINTS.map(([to, label]) => (
        <List.Item
          key={to}
          title={`Rewind ${label}`}
          icon={Icon.RotateAntiClockwise}
          subtitle={`Put the desk back the way it was ${label} ago`}
          actions={
            <ActionPanel>
              <Action
                title="Rewind"
                icon={Icon.ArrowRight}
                onAction={() => act(["rewind", "--to", to], `Rewound ${label}`)}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
