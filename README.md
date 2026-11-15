# docker-nito

A Docker image that runs a full [Nito](https://nito.network/) node, compiled from source. No wallet, no GUI, no dashboard - just `nitod` and `nito-cli`, for anyone wanting to run a Nito node with Docker. Built for `linux/amd64` and `linux/arm64`.

```
ghcr.io/nito-tools/docker-nito:latest     newest build of the newest Nito Core
ghcr.io/nito-tools/docker-nito:v4.0.0     newest build of Nito Core v4.0.0
ghcr.io/nito-tools/docker-nito:v4.0.0-1   one exact build, never changes
```

See [Versions and releases](#versions-and-releases).

## Easiest way: Umbrel

If you have an [Umbrel](https://umbrel.com/) home server, the **Nito** app runs this image for you, with a dashboard showing new blocks, sync progress and a map of your peers. Add the community app store `https://github.com/saltedlolly/umbrel-app-store` in the Umbrel App Store (the menu at the top right, then Community App Stores), then install Nito. Details: [saltedlolly-nito](https://github.com/saltedlolly/umbrel-app-store/tree/master/saltedlolly-nito). The dashboard is a separate container, [nito-dashboard](https://github.com/saltedlolly/umbrel-app-store/tree/master/saltedlolly-nito/docker-containers/nito-dashboard), that talks to this one over RPC.

## Running it with Docker

**Mount a volume at `/data`.** Everything the node keeps (the blockchain, chainstate, indexes, peers, `nito.conf`) lives there. Without a volume, Docker gives the container an anonymous volume: a restart keeps it, but when you replace the container to upgrade (`docker rm` then `docker run` with the new image), the new container starts empty and syncs the whole chain again, while the old data sits orphaned on disk.

With `docker run`:

```bash
docker volume create nito-data

docker run -d --name nito \
  --restart unless-stopped \
  -v nito-data:/data \
  -p 8820:8820 \
  -e NITO_RPC_USER=nito \
  -e NITO_RPC_PASSWORD='choose-a-long-random-password' \
  ghcr.io/nito-tools/docker-nito:v4.0.0
```

To upgrade, pull the new image, then remove and recreate the container with the same `-v nito-data:/data`. The chain is kept.

```bash
docker pull ghcr.io/nito-tools/docker-nito:v4.0.0
docker rm -f nito
docker run -d --name nito ...   # the same command as above
```

With Docker Compose:

```yaml
services:
  nito:
    image: ghcr.io/nito-tools/docker-nito:v4.0.0
    restart: unless-stopped
    ports:
      - "8820:8820"
    environment:
      NITO_RPC_USER: nito
      NITO_RPC_PASSWORD: choose-a-long-random-password
    volumes:
      - nito-data:/data

volumes:
  nito-data:
```

Or use a host folder instead of a named volume, e.g. `-v /srv/nito:/data`. The container fixes the folder's ownership on start, so it doesn't matter who created it.

Useful commands:

```bash
docker logs -f nito
docker exec nito nito-cli -datadir=/data -conf=/data/nito.conf getblockchaininfo
```

Notes:

- **Port 8820** is for other nodes to connect to yours. Forward it on your router to help the network. Don't publish the RPC port (8825) to the internet; containers on the same Docker network can reach it without publishing it.
- **`nito.conf` is rewritten on every start** from the environment variables below, so change settings there, not in the file.
- **There's no wallet.** The image is built without one, so there are no keys in the container to back up or lose.
- **Backups:** the chain data can always be downloaded again, so there's no need to back up `blocks`, `chainstate` or `indexes` (they're most of the size).

## Why build from source

No official Nito Docker image exists, and upstream's own published release binaries have no independent build attestation: there's no reproducible-build signing chain, and the `SHA256SUMS` file is unsigned. (From v4.0.0 they're built by a GitHub Actions run in Nito-core and then attached to the release by hand; v3 and older were built and uploaded by hand.) This image compiles `nitod`/`nito-cli` directly from [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)'s tagged source instead of trusting a pre-built binary, using Nito-core's own (inherited from Bitcoin Core, unmodified) `depends/` cross-compilation system.

## Architecture

Multi-arch, cross-compiling through `depends/` rather than emulating compilation under QEMU: the builder stage always runs natively on the build host (`--platform=$BUILDPLATFORM`), regardless of which architecture is being produced. Built with wallet/Qt/UPnP/NAT-PMP/ZMQ/USDT all disabled - this image is a node only, nothing else.

From v4, Nito Core builds its Orchard proof engine in Rust even with the wallet turned off, so the builder stage is the official `rust` image for the same Debian release as the runtime stage (Debian 13 trixie, set by `DEBIAN_RELEASE` in the Dockerfile), using the Rust version Nito Core pins in its `rust-toolchain.toml`.

## Nito Core version and updates

The Nito Core version is set in one place, the `ARG` lines at the top of the [Dockerfile](Dockerfile):

- `NITO_CORE_TAG`: the release tag to build, e.g. `v4.0.0`.
- `NITO_CORE_COMMIT`: the commit that tag pointed to when it was reviewed. The build fails if the tag has since been moved.
- `RUST_VERSION`: must match the tag's `rust-toolchain.toml`. The build fails if it doesn't.

Updates are automatic up to the point of publishing:

1. Once a day, [check-nito-core.yml](.github/workflows/check-nito-core.yml) compares Nito Core's latest release with the Dockerfile. When there's a newer one, it opens a pull request that updates the three `ARG`s, with the release notes, the pinned commit and whether the tag is signed, and starts a test build.
2. [build-publish.yml](.github/workflows/build-publish.yml) builds both architectures on every pull request without publishing anything.
3. Merging to `main` publishes the image and creates a GitHub Release (see below).

New Nito Core releases are often hard forks or need build changes (v4 added Rust), so a person reads the release notes and merges each update.

## Versions and releases

Every published image gets a version made of the Nito Core version and a build number: `v4.0.0-1`, `v4.0.0-2`, and so on. The number goes up whenever the image is rebuilt with the same Nito Core version (a fix to the entrypoint or Dockerfile, or newer Debian packages), and starts again at 1 for a new Nito Core version.

| Tag | Points to | Changes? |
|---|---|---|
| `v4.0.0-1` | one exact build | Never |
| `v4.0.0` | the newest build of Nito Core v4.0.0 | Yes, with each rebuild |
| `latest` | the newest build of all | Yes |

Each published build has a [GitHub Release](https://github.com/Nito-Tools/docker-nito/releases) with the same name, listing what changed and the image digest. To stay on one exact build, pin the numbered tag, or the digest as the Umbrel app does: `ghcr.io/nito-tools/docker-nito:v4.0.0-1@sha256:...`.

The image's labels record where it came from: `docker inspect` shows the docker-nito commit (`org.opencontainers.image.revision`), its version, and the Nito Core version and commit (`network.nito.core.version`, `network.nito.core.commit`).

**Debian security updates.** Builds reuse cached layers, so a normal rebuild wouldn't pick up new Debian packages. On the 3rd of each month, the workflow checks the published image for Debian package updates. If there are any, it rebuilds without the cache and publishes the next build number, with the updated packages listed in its release. If there are none, nothing is built or published. To rebuild without the cache at any other time, run "Build and publish" by hand on `main` with "Rebuild without cache" ticked.

Builds published before numbering started (`v3.0.1`, and the first `v4.0.0`) have no number or release.

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
