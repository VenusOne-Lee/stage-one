import { closeMainWindow, showHUD, showToast, Toast } from "@raycast/api";
import { stage } from "./stage";

/** Runs a desk-changing command, closing Raycast so the desk is visible, then shows the result. */
export async function act(args: string[], done: string) {
  try {
    await closeMainWindow();
    const message = await stage(...args);
    await showHUD(message || done);
  } catch (e) {
    await showToast({ style: Toast.Style.Failure, title: "Stage One", message: (e as Error).message });
  }
}
