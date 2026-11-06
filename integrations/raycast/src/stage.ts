import { execFile } from "child_process";
import { existsSync } from "fs";
import { promisify } from "util";

const run = promisify(execFile);

/** Where Stage One's `stage` command may live: installed on the PATH, or inside the app. */
const CANDIDATES = [
  "/usr/local/bin/stage",
  "/opt/homebrew/bin/stage",
  "/Applications/Stage One.app/Contents/Helpers/stage",
];

export class StageError extends Error {}

export function stagePath(): string {
  const found = CANDIDATES.find((p) => existsSync(p));
  if (!found) throw new StageError("Stage One isn’t installed. Get it from github.com/VenusOne-Lee/stage-one.");
  return found;
}

export interface Scene {
  name: string;
  windows: number;
  groups: number;
  current?: boolean;
}

export interface Group {
  name: string;
  index: number;
  windows: number;
  active?: boolean;
}

export interface Listing {
  scenes: Scene[];
  groups: Group[];
  layouts: string[];
}

const DEFAULT_LAYOUTS = ["free", "halves", "focus", "thirds", "grid"];

/** `stage list --json`: scenes, groups and layouts. */
export async function list(): Promise<Listing> {
  try {
    const { stdout } = await run(stagePath(), ["list", "--json"], { timeout: 5000 });
    const reply = JSON.parse(stdout);
    return {
      scenes: reply.scenes ?? [],
      groups: reply.groups ?? [],
      layouts: reply.layouts?.length ? reply.layouts : DEFAULT_LAYOUTS,
    };
  } catch (e) {
    if (e instanceof StageError) throw e;
    throw new StageError("Stage One isn’t running. Open it, then try again.");
  }
}

/** Runs a `stage` command and returns its message. */
export async function stage(...args: string[]): Promise<string> {
  try {
    const { stdout } = await run(stagePath(), args, { timeout: 15000 });
    return stdout.trim();
  } catch (e) {
    if (e instanceof StageError) throw e;
    const err = e as { stderr?: string; stdout?: string; message: string };
    throw new StageError((err.stderr || err.stdout || err.message).trim());
  }
}

export function plural(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? "" : "s"}`;
}

export function title(layout: string): string {
  return layout.charAt(0).toUpperCase() + layout.slice(1);
}
