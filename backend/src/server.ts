import express from "express";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { config } from "./config.js";
import { startNitod, waitForRpcReady } from "./nitod.js";
import { getStatsWidget, getSyncWidget, getUptimeWidget } from "./widgets.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  await startNitod();
  console.log("Waiting for nitod RPC to become ready...");
  await waitForRpcReady();
  console.log("nitod RPC ready");

  const app = express();

  app.get("/api/widget/sync", async (_req, res) => {
    try {
      res.json(await getSyncWidget());
    } catch (err) {
      res.status(503).json({ error: (err as Error).message });
    }
  });

  app.get("/api/widget/stats", async (_req, res) => {
    try {
      res.json(await getStatsWidget());
    } catch (err) {
      res.status(503).json({ error: (err as Error).message });
    }
  });

  app.get("/api/widget/uptime", async (_req, res) => {
    try {
      res.json(await getUptimeWidget());
    } catch (err) {
      res.status(503).json({ error: (err as Error).message });
    }
  });

  app.use(express.static(join(__dirname, "..", "public")));

  app.listen(config.httpPort, () => {
    console.log(`Dashboard listening on :${config.httpPort}`);
  });
}

main().catch((err) => {
  console.error("Fatal startup error:", err);
  process.exit(1);
});
