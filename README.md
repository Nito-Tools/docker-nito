# docker-nito

A self-contained Docker image that runs a full [Nito](https://nito.network/) node with an original web dashboard (block height, sync progress, peers, mempool, uptime), built for the [Umbrel](https://umbrel.com/) community app store package at [saltedlolly/umbrel-app-store](https://github.com/saltedlolly/umbrel-app-store), but usable standalone.

## Why build from source

No official Nito Docker image exists, and upstream's own published release binaries have no independent build attestation (no reproducible-build signing chain, and no CI builds the Linux/ARM64 binaries it actually publishes - they're uploaded manually). This image compiles `nitod`/`nito-cli` directly from [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)'s tagged source instead of trusting a pre-built binary, using Nito-core's own (inherited from Bitcoin Core, unmodified) `depends/` cross-compilation system.

## Why an original dashboard, not a fork

The obvious template for a node dashboard like this is [getumbrel/umbrel-bitcoin](https://github.com/getumbrel/umbrel-bitcoin), whose backend/UI approach (spawn the node as a child process, poll standard JSON-RPC calls) transfers cleanly to any Bitcoin Core-compatible fork. That repo is licensed PolyForm Noncommercial 1.0.0, though, which is a genuine gray area for a store that accepts sponsorships - so this is an independent implementation, inspired by that project's general approach (which isn't copyrightable) but sharing none of its code.

## Architecture

- **Builder stage** (multi-arch, runs natively on the build host via `--platform=$BUILDPLATFORM`, cross-compiling through `depends/` rather than emulating compilation under QEMU): clones a pinned Nito-core tag, builds `nitod`/`nito-cli` with wallet/Qt/UPnP/NAT-PMP/ZMQ/USDT all disabled - this app is a read-only monitoring dashboard, not a wallet or mining manager.
- **Backend** (`backend/`, Node/TypeScript): writes `nito.conf`, spawns `nitod` as a child process, and exposes `/api/widget/{sync,stats,uptime}` by polling standard Bitcoin Core-compatible JSON-RPC (`getblockchaininfo`, `getnetworkinfo`, `getmempoolinfo`, `uptime`) - all present unmodified in Nito-core, confirmed by reading `src/rpc/*.cpp` directly.
- **Frontend** (`frontend/`, React + Vite): a small dashboard rendering those widgets, built to static files and served by the backend.

The Debian version of the builder's base image (`node:22-bookworm`) is deliberately matched to the final runtime image's base (`node:22-slim`, also bookworm) - building `nitod` against a newer glibc than the runtime stage ships causes it to fail at startup with `GLIBC_2.3x not found`, hit during development.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `NITO_NETWORK` | `main` | `main`, `test`, or `regtest` |
| `NITO_DATA_DIR` | `/data` | Node data directory (volume mount target) |
| `NITO_RPC_PORT` | `8825` | Internal RPC port (never exposed outside the container - the backend is the only client) |
| `NITO_P2P_PORT` | `8820` | Swarm/peer port - publish this one |
| `PORT` | `3000` | Dashboard HTTP port |

RPC credentials are generated internally on every startup and never read from the environment - nothing outside this container ever needs to authenticate to that endpoint.

## Building locally

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t docker-nito .
```

## Credits

- **Nito**: [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)
- **Packaging, backend, and dashboard**: Nito-Tools
