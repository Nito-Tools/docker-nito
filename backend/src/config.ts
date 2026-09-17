import { randomBytes } from "node:crypto";

type Network = "main" | "test" | "regtest";

function readNetwork(): Network {
  const value = process.env.NITO_NETWORK ?? "main";
  if (value !== "main" && value !== "test" && value !== "regtest") {
    throw new Error(`Invalid NITO_NETWORK: ${value} (expected main, test, or regtest)`);
  }
  return value;
}

export const config = {
  dataDir: process.env.NITO_DATA_DIR ?? "/data",
  nitodBin: process.env.NITO_BIN ?? "/usr/local/bin/nitod",
  nitoCliBin: process.env.NITO_CLI_BIN ?? "/usr/local/bin/nito-cli",
  httpPort: Number(process.env.PORT ?? 3000),
  network: readNetwork(),
  rpcPort: Number(process.env.NITO_RPC_PORT ?? 8825),
  p2pPort: Number(process.env.NITO_P2P_PORT ?? 8820),
  // Generated once and written to nito.conf on first start (see nitod.ts) -
  // not read from the environment, since nothing outside this container
  // ever needs to authenticate to this RPC endpoint.
  rpcUser: "nitodashboard",
  rpcPassword: randomBytes(24).toString("hex"),
};

export function renderNitoConf(): string {
  // Network selection (regtest=1/testnet=1) must be a top-level directive,
  // but network-specific settings like bind/port/rpcbind/rpcport must live
  // under a matching [main]/[test]/[regtest] section once a non-default
  // network is selected via the config file - Nito (inheriting Bitcoin
  // Core's config parser) rejects them as unqualified top-level settings
  // otherwise, caught only by actually running nitod against this file.
  const sectionHeader = { main: "[main]", test: "[test]", regtest: "[regtest]" }[config.network];

  const lines = ["server=1", `rpcuser=${config.rpcUser}`, `rpcpassword=${config.rpcPassword}`];
  if (config.network === "test") lines.push("testnet=1");
  if (config.network === "regtest") lines.push("regtest=1");
  lines.push(
    "",
    sectionHeader,
    "rpcbind=127.0.0.1",
    "rpcallowip=127.0.0.1",
    `rpcport=${config.rpcPort}`,
    "listen=1",
    "bind=0.0.0.0",
    `port=${config.p2pPort}`,
    "",
  );
  return lines.join("\n");
}
