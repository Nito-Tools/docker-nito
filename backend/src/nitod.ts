import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { setTimeout as sleep } from "node:timers/promises";
import { config, renderNitoConf } from "./config.js";
import { rpcCall } from "./rpc.js";

export async function startNitod(): Promise<void> {
  await mkdir(config.dataDir, { recursive: true });
  // Always rewritten on startup, matching the freshly-generated in-memory
  // rpcPassword each run - nito.conf is internal plumbing between this
  // process and its own child nitod, not user-facing config, so there's
  // no reason to try to persist/reuse it across restarts.
  await writeFile(`${config.dataDir}/nito.conf`, renderNitoConf());

  const child = spawn(
    config.nitodBin,
    ["-datadir=" + config.dataDir, "-conf=" + config.dataDir + "/nito.conf", "-printtoconsole"],
    { stdio: "inherit" },
  );

  child.on("exit", (code, signal) => {
    console.error(`nitod exited (code=${code}, signal=${signal}) - exiting so the container restarts`);
    process.exit(1);
  });

  process.on("SIGTERM", () => child.kill("SIGTERM"));
  process.on("SIGINT", () => child.kill("SIGINT"));
}

export async function waitForRpcReady(timeoutMs = 120_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      await rpcCall("getnetworkinfo");
      return;
    } catch {
      await sleep(1000);
    }
  }
  throw new Error(`nitod RPC did not become ready within ${timeoutMs}ms`);
}
