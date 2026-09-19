# docker-nito

A Docker image that runs a full [Nito](https://nito.network/) node, compiled from source. No wallet, no GUI, no dashboard - just `nitod`, built for anyone wanting to run a Nito node via Docker.

Used as the node container for the [saltedlolly/umbrel-app-store](https://github.com/saltedlolly/umbrel-app-store) `saltedlolly-nito` Umbrel package, paired with [nito-dashboard](https://github.com/saltedlolly/nito-dashboard) as a separate companion container for the web UI - see that repo for why the dashboard isn't bundled in here.

## Why build from source

No official Nito Docker image exists, and upstream's own published release binaries have no independent build attestation (no reproducible-build signing chain, and no CI builds the Linux/ARM64 binaries it actually publishes - they're uploaded manually). This image compiles `nitod`/`nito-cli` directly from [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)'s tagged source instead of trusting a pre-built binary, using Nito-core's own (inherited from Bitcoin Core, unmodified) `depends/` cross-compilation system.

## Architecture

Multi-arch, cross-compiling through `depends/` rather than emulating compilation under QEMU: the builder stage always runs natively on the build host (`--platform=$BUILDPLATFORM`), regardless of which architecture is being produced. Built with wallet/Qt/UPnP/NAT-PMP/ZMQ/USDT all disabled - this image is a node only, nothing else.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `NITO_NETWORK` | `main` | `main`, `test`, or `regtest` |
| `NITO_DATA_DIR` | `/data` | Node data directory (volume mount target) |
| `NITO_RPC_USER` | *(required)* | RPC username |
| `NITO_RPC_PASSWORD` | *(required)* | RPC password |
| `NITO_RPC_PORT` | `8825` | RPC port |
| `NITO_RPC_ALLOW_IP` | `0.0.0.0/0` | RPC allowlist CIDR - callers wanting a dashboard/wallet container to reach RPC without opening it to everything should scope this to their own subnet (Umbrel's own `saltedlolly-nito` package passes `${NETWORK_IP}/16`, Umbrel's documented mechanism for exactly this) |
| `NITO_P2P_PORT` | `8820` | Swarm/peer port - publish this one |

## Building locally

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t docker-nito .
```

## Credits

- **Nito**: [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)
- **Packaging**: Nito-Tools
