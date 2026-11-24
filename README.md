# nito-docker

A Docker image that runs a full [Nito](https://nito.network/) node, using Nito Core's official, verified release binaries (or compiled from source if you build it yourself, see [Building from source](#building-from-source)). No wallet, no GUI, no dashboard - just `nitod` and `nito-cli`, for anyone wanting to run a Nito node with Docker. Built for `linux/amd64` and `linux/arm64`.

```
ghcr.io/nito-tools/nito-docker:latest     newest build of the newest Nito Core
ghcr.io/nito-tools/nito-docker:v4.0.0     newest build of Nito Core v4.0.0
ghcr.io/nito-tools/nito-docker:v4.0.0-1   one exact build, never changes
```

See [Versions and releases](#versions-and-releases).

**Moved:** this repository and image used to be called `docker-nito`. Builds up to v4.0.0-3 stay at `ghcr.io/nito-tools/docker-nito`, but new builds are only published here, so switch to `ghcr.io/nito-tools/nito-docker`.

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
  ghcr.io/nito-tools/nito-docker:v4.0.0
```

To upgrade, pull the new image, then remove and recreate the container with the same `-v nito-data:/data`. The chain is kept.

```bash
docker pull ghcr.io/nito-tools/nito-docker:v4.0.0
docker rm -f nito
docker run -d --name nito ...   # the same command as above
```

With Docker Compose:

```yaml
services:
  nito:
    image: ghcr.io/nito-tools/nito-docker:v4.0.0
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

## Where the binaries come from

The published images use **Nito Core's official Linux release binaries**, `nitod` and `nito-cli` from the `x86_64` and `aarch64` tarballs on [Nito Core's releases page](https://github.com/NitoNetwork/Nito-core/releases), so Docker users run exactly what everyone else runs. Before a new version is used, [scripts/verify-nito-core-release.sh](scripts/verify-nito-core-release.sh) checks:

1. `SHA256SUMS` is signed with Nito Core's Minisign release key. The key is pinned in this repo as [nito-core-release.pub](nito-core-release.pub), copied from Nito Core's `contrib/release/nito-core-release.pub`; if Nito Core ever changes key, a person has to review and replace it.
2. Both tarballs match `SHA256SUMS`.
3. Both tarballs have a GitHub build attestation from Nito Core's own release workflow (`build-release.yml`), so they were built by GitHub Actions from Nito Core's repository, not uploaded by hand.

The tarballs' checksums are then pinned in the Dockerfile, and the build fails if a download doesn't match. The checks run when the update pull request is opened and again before every publish.

The official binaries include the wallet, so the image sets `disablewallet=1`: it's a node only. Pass `-disablewallet=0` as an argument to turn the wallet on.

### Building from source

If you'd rather not trust the release binaries, build the image yourself with `NITO_BUILD=source`. It compiles `nitod`/`nito-cli` from [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)'s tagged source, at the commit pinned in the Dockerfile, using Nito Core's own (inherited from Bitcoin Core, unmodified) `depends/` cross-compilation system:

```bash
git clone https://github.com/Nito-Tools/nito-docker.git
cd nito-docker
docker buildx build --build-arg NITO_BUILD=source -t nito-docker:source --load .
```

It takes about an hour. The result is a node only: wallet, Qt, UPnP, NAT-PMP, ZMQ and USDT are all left out. `docker inspect` shows which kind an image is in the `network.nito.core.build` label (`release` or `source`).

The compile stage always runs natively on the build host (`--platform=$BUILDPLATFORM`) and cross-compiles through `depends/` rather than emulating under QEMU. From v4, Nito Core builds its Orchard proof engine in Rust even with the wallet off, so it uses the official `rust` image for the same Debian release as the runtime stage (Debian 13 trixie, `DEBIAN_RELEASE` in the Dockerfile), with the Rust version Nito Core pins in its `rust-toolchain.toml`. The source build is tested by running "Build and publish" by hand with `nito_build` set to `source`; those builds are never published.

## Nito Core version and updates

The Nito Core version is set in one place, the `ARG` lines at the top of the [Dockerfile](Dockerfile):

- `NITO_CORE_TAG`: the release, e.g. `v4.1.0`.
- `NITO_CORE_SHA256_AMD64`, `NITO_CORE_SHA256_ARM64`: the checksums of that release's Linux tarballs. The build fails if a download doesn't match.
- `NITO_CORE_COMMIT`: the commit that tag pointed to when it was reviewed. A source build fails if the tag has since been moved.
- `RUST_VERSION`: must match the tag's `rust-toolchain.toml` (source builds only). The build fails if it doesn't.

Updates are automatic up to the point of publishing:

1. Once a day, [check-nito-core.yml](.github/workflows/check-nito-core.yml) compares Nito Core's latest release with the Dockerfile. When there's a newer one, it verifies the release's Linux files (see [Where the binaries come from](#where-the-binaries-come-from)), then opens a pull request that updates the `ARG`s, with the release notes, the pinned commit and checksums, and whether the tag is signed, and starts a test build. If the release doesn't have its Linux files and signature yet, it tries again the next day; if they fail the checks, the run fails and no pull request is opened.
2. [build-publish.yml](.github/workflows/build-publish.yml) builds both architectures on every pull request without publishing anything (a couple of minutes).
3. Merging to `main` checks the release files again, publishes the image and creates a GitHub Release (see below).

New Nito Core releases are often hard forks, so a person reads the release notes and merges each update.

## Versions and releases

Every published image gets a version made of the Nito Core version and a build number: `v4.0.0-1`, `v4.0.0-2`, and so on. The number goes up whenever the image is rebuilt with the same Nito Core version (a fix to the entrypoint or Dockerfile, or newer Debian packages), and starts again at 1 for a new Nito Core version.

| Tag | Points to | Changes? |
|---|---|---|
| `v4.0.0-1` | one exact build | Never |
| `v4.0.0` | the newest build of Nito Core v4.0.0 | Yes, with each rebuild |
| `latest` | the newest build of all | Yes |

Each published build has a [GitHub Release](https://github.com/Nito-Tools/nito-docker/releases) with the same name, listing what changed and the image digest. To stay on one exact build, pin the numbered tag, or the digest as the Umbrel app does: `ghcr.io/nito-tools/nito-docker:v4.0.0-1@sha256:...`.

The image's labels record where it came from: `docker inspect` shows the nito-docker commit (`org.opencontainers.image.revision`), its version, the Nito Core version and commit (`network.nito.core.version`, `network.nito.core.commit`), and whether it uses the official binaries or was built from source (`network.nito.core.build`).

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
| `NITO_TXINDEX` | *(unset)* | `txindex`: look up any transaction by its ID with `getrawtransaction`, as explorers do. `0` or `1`; unset keeps Nito Core's default (on) |
| `NITO_TRANSPARENTHISTORYINDEX` | *(unset)* | `transparenthistoryindex`: restore a wallet from its recovery phrase on a node that already has the chain. Day-to-day wallet use doesn't need it. `0` or `1`; unset keeps Nito Core's default (on) |
| `NITO_ORCHARDINDEX` | *(unset)* | `orchardindex`: needed for any Bech32x (private) wallet use and for restoring private funds. Small until Orchard activates at block 1,165,432, then grows with use. `0` or `1`; unset keeps Nito Core's default (on) |

**Indexes.** Nito Core v4 builds all three indexes by default. A node with no wallet (for example one that only supports the network) needs none of them: on mainnet they took about 700 MB at block 1.1 million, mostly `transparenthistoryindex`. Setting one to `0` switches it off and **deletes its files** at the next start; setting it back to `1` (or unsetting it) rebuilds it from the chain. Pruning (`-prune`) can't be combined with `txindex` or `transparenthistoryindex` switched on.

**Other `nitod` options.** Anything given as the container's command is passed straight to `nitod`, e.g. `-dbcache=1000 -maxconnections=40` after the image name in `docker run`, or in Compose:

```yaml
    command: ["-dbcache=1000", "-maxconnections=40"]
```

## Building locally

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t nito-docker .
```

This uses the official binaries. Add `--build-arg NITO_BUILD=source` to compile instead (see [Building from source](#building-from-source)).

## Credits

- **Nito**: [NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)
- **Packaging**: Nito-Tools
