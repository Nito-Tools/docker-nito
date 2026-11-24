# syntax=docker/dockerfile:1
#
# Just the Nito node - nitod/nito-cli, plus a minimal entrypoint. No
# dashboard/UI in this image: that's Umbrel-specific and lives as its own
# companion image in the saltedlolly-nito Umbrel app package instead,
# connecting to this container's RPC port over the network rather than
# being bundled in here - this image is meant to be generically useful to
# anyone wanting to run Nito via Docker, not just Umbrel users.
#
# Where nitod/nito-cli come from is chosen with the NITO_BUILD build
# argument:
#
#   release (default, and what the published images use)
#       Nito Core's official Linux release binaries. The tarball for the
#       target architecture is downloaded from the GitHub release and must
#       match the SHA256 pinned below, or the build fails. Those checksums
#       are only written here after scripts/verify-nito-core-release.sh has
#       checked the release's Minisign-signed SHA256SUMS and GitHub build
#       attestations (the check-nito-core workflow does this before opening
#       its pull request, and build-publish checks again before publishing).
#
#   source
#       Compiles Nito Core from its tagged source (the pinned commit), using
#       its own depends/ cross-compilation system - for anyone who'd rather
#       not trust the release binaries:
#         docker buildx build --build-arg NITO_BUILD=source -t nito-docker .
#       Takes about an hour.
#
# Only the stages the chosen option needs are built.

# The Nito Core release to build. This is the one place the version is
# set: the CI workflow reads these lines, and the check-nito-core workflow
# opens a pull request that updates them when a new release comes out.
# NITO_CORE_COMMIT pins the commit the tag pointed to when it was
# reviewed, so the build fails if the tag is ever moved.
# NITO_CORE_SHA256_* are the release tarballs' checksums (NITO_BUILD=release).
# RUST_VERSION must match the tag's rust-toolchain.toml (Nito Core v4+
# builds its Orchard proof engine in Rust, even with the wallet off; only
# used by NITO_BUILD=source).
ARG NITO_CORE_TAG=v4.1.0
ARG NITO_CORE_COMMIT=460a0d1da6e7b2b6e3fd117c151b9d2bc764015a
ARG NITO_CORE_SHA256_AMD64=5106311ba78c0f7c7042b2c6c777d62dd566fc8dd34c4feaebdf7fd2baf3a66e
ARG NITO_CORE_SHA256_ARM64=7ea550602d4d2ff4ff4ea16e09da3c51e0b6ef81498589f58459e124ebdb1180
ARG RUST_VERSION=1.97.0
# release or source, see above.
ARG NITO_BUILD=release
# Debian release for all stages. The source build's and the runtime's must
# match: nitod is built against the builder's glibc and has to run on the
# same one. (The official release binaries are built to run on older
# glibc versions too.) Change it by hand
# when moving to a new Debian release (trixie = Debian 13).
ARG DEBIAN_RELEASE=trixie

# NITO_BUILD=release: the official binaries for the target architecture.
# Only a download, so it runs on the build host's own platform.
FROM --platform=$BUILDPLATFORM debian:${DEBIAN_RELEASE}-slim AS release
ARG NITO_CORE_TAG
ARG NITO_CORE_SHA256_AMD64
ARG NITO_CORE_SHA256_ARM64
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) triplet=x86_64-linux-gnu; sum="$NITO_CORE_SHA256_AMD64" ;; \
      arm64) triplet=aarch64-linux-gnu; sum="$NITO_CORE_SHA256_ARM64" ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    file="nito-${NITO_CORE_TAG#v}-$triplet.tar.gz"; \
    curl -fsSL --retry 3 -o "/tmp/$file" \
      "https://github.com/NitoNetwork/Nito-core/releases/download/$NITO_CORE_TAG/$file"; \
    if ! echo "$sum  /tmp/$file" | sha256sum -c -; then \
      echo "$file doesn't match the SHA256 pinned in the Dockerfile. Refusing to use it." >&2; \
      exit 1; \
    fi; \
    mkdir /out; \
    tar xzf "/tmp/$file" -C /out --strip-components=1 bin/nitod bin/nito-cli; \
    rm "/tmp/$file"

# NITO_BUILD=source: compile Nito Core.
# Same Debian release as the runtime stage - must match its glibc exactly, or the
# compiled nitod binary fails at startup with GLIBC_2.3x "version not
# found" errors (hit during development building against a newer glibc
# than the runtime stage shipped). The official rust image is Debian
# with rustup and the pinned Rust toolchain already installed.
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-${DEBIAN_RELEASE} AS source
ARG NITO_CORE_TAG
ARG NITO_CORE_COMMIT
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libtool autotools-dev automake pkg-config bsdmainutils \
    python3 git curl ca-certificates cmake ninja-build \
    g++-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --branch "$NITO_CORE_TAG" --depth 1 https://github.com/NitoNetwork/Nito-core.git . \
    && actual="$(git rev-parse HEAD)" \
    && if [ "$actual" != "$NITO_CORE_COMMIT" ]; then \
         echo "Tag $NITO_CORE_TAG points to $actual, expected $NITO_CORE_COMMIT. Refusing to build a moved tag." >&2; \
         exit 1; \
       fi

# Map Docker's TARGETARCH to the depends/ host triplet and the matching
# Rust target.
RUN case "$TARGETARCH" in \
      amd64) echo x86_64-linux-gnu > /tmp/host_triplet; echo x86_64-unknown-linux-gnu > /tmp/rust_target ;; \
      arm64) echo aarch64-linux-gnu > /tmp/host_triplet; echo aarch64-unknown-linux-gnu > /tmp/rust_target ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac

# Nito Core's rust-toolchain.toml picks the toolchain; fail early if it
# doesn't match RUST_VERSION rather than letting rustup download another
# one mid-build. Then add the target-architecture standard library.
RUN if [ -f rust-toolchain.toml ]; then \
      want="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' rust-toolchain.toml)"; \
      have="$(rustc --version | cut -d' ' -f2)"; \
      if [ "$want" != "$have" ]; then \
        echo "Nito Core $NITO_CORE_TAG wants Rust $want but this image has $have: update RUST_VERSION." >&2; \
        exit 1; \
      fi; \
      rustup target add "$(cat /tmp/rust_target)"; \
    fi

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
#
# Nito Core's configure only passes --target to cargo for aarch64 hosts,
# so building amd64 on an arm64 machine (e.g. an Apple Silicon Mac) would
# build the Orchard library for the wrong architecture. Always set the
# Rust target and its linker explicitly instead. The make variable is
# harmless on v3 and older, which have no Rust code.
RUN RUST_TARGET="$(cat /tmp/rust_target)" \
    && export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc \
    && export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    && make -j$(nproc) src/nitod NITO_ORCHARD_FFI_CARGO_TARGET="$RUST_TARGET" \
    && make -j$(nproc) src/nito-cli NITO_ORCHARD_FFI_CARGO_TARGET="$RUST_TARGET"
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
    "$STRIP" src/nitod src/nito-cli \
    && mkdir /out && cp src/nitod src/nito-cli /out/

# Whichever of the two NITO_BUILD chose.
FROM ${NITO_BUILD} AS nito-binaries


FROM debian:${DEBIAN_RELEASE}-slim
ARG NITO_BUILD
LABEL network.nito.core.build="$NITO_BUILD"
# upgrade as well as install: the debian slim image is only
# refreshed every few weeks, and the monthly no-cache rebuild (see
# build-publish.yml) is meant to pick up security updates published since.
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends tini gosu ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -m -d /data nito \
    && mkdir -p /data && chown nito:nito /data

COPY --from=nito-binaries /out/nitod /out/nito-cli /usr/local/bin/
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
