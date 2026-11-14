// Early warning for pi. The `tool_call` event can block a call: return { block: true, reason }.
// Install (advisory only): cp this file to ~/.pi/agent/extensions/hk.ts
// The rule itself lives in the git hook, because pi can also run with extensions switched off.
// Event shape is checked against pi 1.5.0 docs/extensions.md: `tool_call` fires before execution,
// and bash carries the command in event.input.command.
import { execFileSync } from "node:child_process";

const HK = `${process.env.HOME}/Work/scripts/harness/hk`;

export default function (pi: any) {
  pi.on("tool_call", async (event: any) => {
    const command = event?.input?.command;
    if (typeof command !== "string") return;
    if (!/git (commit|push)/.test(command)) return;
    try {
      execFileSync(HK, ["check"], { stdio: "pipe" });
    } catch (error: any) {
      const detail = String(error?.stderr ?? error?.message ?? "").trim();
      return { block: true, reason: `hk: ${detail || "no fresh receipt and review"}. Run hk verify, then hk review.` };
    }
  });
}
