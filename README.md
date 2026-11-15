# docker-nito

A Docker image that runs a full [Nito](https://nito.network/) node, compiled from source. No wallet, no GUI, no dashboard - just `nitod`, built for anyone wanting to run a Nito node via Docker.

Used as the node container for the [saltedlolly/umbrel-app-store](https://github.com/saltedlolly/umbrel-app-store) `saltedlolly-nito` Umbrel package, paired with [nito-dashboard](https://github.com/saltedlolly/nito-dashboard) as a separate companion container for the web UI - see that repo for why the dashboard isn't bundled in here.

## Why build from source

No official Nito Docker image exists, and upstream's own published release binaries have no independent build attestation: there's no reproducible-build signing chain, and the `SHA256SUMS` file is unsigned. (From v4.0.0 they're built by a GitHub Actions run in Nito-core and then attached to the release by hand; v3 and older were built and uploaded by hand.) This image compiles `nitod`/`nito-cli` directly from [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)'s tagged source instead of trusting a pre-built binary, using Nito-core's own (inherited from Bitcoin Core, unmodified) `depends/` cross-compilation system.

## Architecture

Multi-arch, cross-compiling through `depends/` rather than emulating compilation under QEMU: the builder stage always runs natively on the build host (`--platform=$BUILDPLATFORM`), regardless of which architecture is being produced. Built with wallet/Qt/UPnP/NAT-PMP/ZMQ/USDT all disabled - this image is a node only, nothing else.

From v4, Nito Core builds its Orchard proof engine in Rust even with the wallet turned off, so the builder stage is the official `rust` image for Debian bookworm, using the Rust version Nito Core pins in its `rust-toolchain.toml`.

## Nito Core version and updates

The Nito Core version is set in one place, the `ARG` lines at the top of the [Dockerfile](Dockerfile):

- `NITO_CORE_TAG`: the release tag to build, e.g. `v4.0.0`.
- `NITO_CORE_COMMIT`: the commit that tag pointed to when it was reviewed. The build fails if the tag has since been moved.
- `RUST_VERSION`: must match the tag's `rust-toolchain.toml`. The build fails if it doesn't.

Updates are automatic up to the point of publishing:

1. Once a day, [check-nito-core.yml](.github/workflows/check-nito-core.yml) compares Nito Core's latest release with the Dockerfile. When there's a newer one, it opens a pull request that updates the three `ARG`s, with the release notes, the pinned commit and whether the tag is signed, and starts a test build.
2. [build-publish.yml](.github/workflows/build-publish.yml) builds both architectures on every pull request without publishing anything.
3. Merging to `main` publishes `ghcr.io/nito-tools/docker-nito:<tag>` and `:latest`.

New Nito Core releases are often hard forks or need build changes (v4 added Rust), so a person reads the release notes and merges each update.

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
