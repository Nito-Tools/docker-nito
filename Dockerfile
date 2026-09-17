# syntax=docker/dockerfile:1
#
# Multi-stage, multi-arch build: compiles nitod/nito-cli from source (no
# official Nito binaries or Docker image exist, and upstream's own releases
# have no independent build attestation - see this repo's README), then
# packages them with an original Node/TypeScript backend and React
# dashboard, neither of which are derived from any existing project's code.
#
# The builder stage always runs on the build host's native platform
# (--platform=$BUILDPLATFORM) regardless of which TARGETARCH is being
# produced, and cross-compiles via Nito-core's own (unmodified, inherited
# from Bitcoin Core) depends/ system - proven working in both directions
# during development (native arm64, and arm64-host-to-x86_64 cross-compile).
# This avoids ever compiling C++ under QEMU emulation, which would be
# extremely slow for a multi-arch build.

ARG NITO_CORE_TAG=v3.0.1

# Debian bookworm, not Ubuntu - must match the glibc of the node:22-slim
# (also bookworm) runtime stage below exactly, or the compiled nitod binary
# fails at startup with GLIBC_2.3x "version not found" errors (hit during
# development building against Ubuntu 24.04's newer glibc while the
# runtime stage's glibc was older).
FROM --platform=$BUILDPLATFORM node:22-bookworm AS nitod-builder
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

# Dashboard scope is block height/sync/peers/mempool/uptime only (no wallet
# UI in this app) - NO_WALLET/NO_QT/NO_UPNP/NO_NATPMP/NO_ZMQ/NO_USDT all
# trim the build to just what nitod/nito-cli need for that, proven in the
# same shape during development.
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
RUN strip src/nitod src/nito-cli


FROM --platform=$BUILDPLATFORM node:22-slim AS frontend-builder
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build


FROM --platform=$BUILDPLATFORM node:22-slim AS backend-builder
WORKDIR /backend
COPY backend/package*.json ./
RUN npm ci
COPY backend/ ./
RUN npm run build


FROM node:22-slim
RUN apt-get update && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -m -d /data nito

COPY --from=nitod-builder /src/src/nitod /src/src/nito-cli /usr/local/bin/
COPY --from=backend-builder /backend/dist /app/dist
COPY --from=backend-builder /backend/node_modules /app/node_modules
COPY --from=backend-builder /backend/package.json /app/package.json
COPY --from=frontend-builder /frontend/dist /app/public

ENV NITO_DATA_DIR=/data \
    NITO_BIN=/usr/local/bin/nitod \
    NITO_CLI_BIN=/usr/local/bin/nito-cli \
    NODE_ENV=production \
    PORT=3000

VOLUME /data
EXPOSE 3000 8820 8820/udp

USER nito
WORKDIR /app
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "dist/server.js"]
