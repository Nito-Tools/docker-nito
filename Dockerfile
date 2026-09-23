# syntax=docker/dockerfile:1
#
# Just the compiled Nito node - nitod/nito-cli, built from source, plus a
# minimal entrypoint. No dashboard/UI in this image: that's Umbrel-specific
# and lives as its own companion image in the saltedlolly-nito Umbrel app
# package instead, connecting to this container's RPC port over the
# network rather than being bundled in here - this image is meant to be
# generically useful to anyone wanting to run Nito via Docker, not just
# Umbrel users, the same way the official ecosystem's own
# getumbrel/umbrel-bitcoin backend pulls compiled binaries from a separate
# node image rather than compiling the node itself alongside its dashboard.
#
# No official Nito Docker image exists, and upstream's own published
# release binaries have no independent build attestation (no reproducible-
# build signing chain, and no CI builds the Linux/ARM64 binaries it
# actually publishes - they're uploaded manually). This compiles from
# NitoNetwork/Nito-core's tagged source instead, using its own (inherited
# from Bitcoin Core, unmodified) depends/ cross-compilation system.
#
# The builder stage always runs on the build host's native platform
# (--platform=$BUILDPLATFORM) regardless of which TARGETARCH is being
# produced, cross-compiling via depends/ rather than under QEMU emulation.

ARG NITO_CORE_TAG=v3.0.1

# Debian bookworm - must match the runtime stage's glibc exactly, or the
# compiled nitod binary fails at startup with GLIBC_2.3x "version not
# found" errors (hit during development building against a newer glibc
# than the runtime stage shipped).
FROM --platform=$BUILDPLATFORM debian:bookworm AS builder
ARG NITO_CORE_TAG
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libtool autotools-dev automake pkg-config bsdmainutils \
    python3 git curl ca-certificates cmake \
    g++-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --branch "$NITO_CORE_TAG" --depth 1 https://github.com/NitoNetwork/Nito-core.git .

# Map Docker's TARGETARCH to the depends/ host triplet.
RUN case "$TARGETARCH" in \
      amd64) echo x86_64-linux-gnu > /tmp/host_triplet ;; \
      arm64) echo aarch64-linux-gnu > /tmp/host_triplet ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac

# This image is node-only: no wallet, no Qt GUI, no UPnP/NAT-PMP/ZMQ/USDT.
RUN cd depends && make HOST="$(cat /tmp/host_triplet)" \
      NO_QT=1 NO_WALLET=1 NO_UPNP=1 NO_NATPMP=1 NO_ZMQ=1 NO_USDT=1 -j$(nproc)

RUN ./autogen.sh
RUN CONFIG_SITE="$(pwd)/depends/$(cat /tmp/host_triplet)/share/config.site" \
    ./configure --disable-tests --disable-bench --disable-fuzz-binary
# Sequential, not `make target1 target2` - Bitcoin Core's (and therefore
# Nito's, unmodified) autotools setup re-enters src/ as an independent
# recursive sub-make per top-level target; requesting both in one `make -j`
# invocation races two sub-makes against the same shared object files
# (hit during development: a corrupted crypto/*.lo from exactly this).
RUN make -j$(nproc) src/nitod && make -j$(nproc) src/nito-cli
# Plain `strip` is the build host's native tool - fine when building
# amd64-on-amd64 or arm64-on-arm64, but on a genuine cross build (e.g. this
# repo's own CI: an amd64 GitHub Actions runner producing the arm64 image)
# it can't process the foreign-architecture binary at all (caught by CI,
# not local testing, since local testing happened to build on matching
# host/target architectures). Use the matching cross-strip tool.
RUN case "$TARGETARCH" in \
      amd64) STRIP=x86_64-linux-gnu-strip ;; \
      arm64) STRIP=aarch64-linux-gnu-strip ;; \
    esac; \
    "$STRIP" src/nitod src/nito-cli


FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends tini gosu ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -m -d /data nito \
    && mkdir -p /data && chown nito:nito /data

COPY --from=builder /src/src/nitod /src/src/nito-cli /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV NITO_DATA_DIR=/data
VOLUME /data
EXPOSE 8820 8820/udp 8825

# Stays root here rather than USER nito - Umbrel (and any other bind-mount
# user) creates the host-side /data directory owned by whatever UID it
# runs as, not UID 1000, so a container that started directly as nito
# could never write to it ("Permission denied" on the very first boot).
# entrypoint.sh fixes ownership while still root, then drops to nito via
# gosu before exec'ing nitod.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
