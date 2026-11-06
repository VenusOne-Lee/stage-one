import { Action, ActionPanel, Form, Icon } from "@raycast/api";
import { useState } from "react";
import { act } from "./act";

export default function SaveScene(props: { name?: string }) {
  const [error, setError] = useState<string>();
  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Save Scene"
            icon={Icon.SaveDocument}
            onSubmit={(v: { name: string }) => {
              const name = v.name.trim();
              if (!name) return setError("Give the scene a name");
              return act(["save", name], `Saved “${name}”`);
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="name"
        title="Scene name"
        placeholder="Deep work"
        defaultValue={props.name}
        error={error}
        onChange={() => setError(undefined)}
      />
      <Form.Description text="Saves every group and window on the desk, so you can put it back later." />
    </Form>
  );
}
