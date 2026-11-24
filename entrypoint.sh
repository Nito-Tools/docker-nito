#!/bin/sh
set -eu

DATA_DIR="${NITO_DATA_DIR:-/data}"
mkdir -p "$DATA_DIR"

# The container starts as root (see Dockerfile) because a bind-mounted
# host directory (e.g. Umbrel's ${APP_DATA_DIR}/data/nito) is created by
# whatever UID the host runs as, not UID 1000 - a fresh mount is normally
# root-owned, so the nito user couldn't write nito.conf on first boot.
# Fix ownership once (skip if already correct, so a large existing chain
# state doesn't pay a recursive chown on every restart), then drop
# privileges before running nitod.
if [ "$(stat -c '%u' "$DATA_DIR")" != "1000" ]; then
  chown -R nito:nito "$DATA_DIR"
fi

NETWORK="${NITO_NETWORK:-main}"
case "$NETWORK" in
  main) SECTION="[main]" ;;
  test) SECTION="[test]" ;;
  regtest) SECTION="[regtest]" ;;
  *) echo "Invalid NITO_NETWORK: $NETWORK (expected main, test, or regtest)" >&2; exit 1 ;;
esac

: "${NITO_RPC_USER:?NITO_RPC_USER is required}"
: "${NITO_RPC_PASSWORD:?NITO_RPC_PASSWORD is required}"

# Network-specific data folder, where nitod keeps its indexes/ directory.
case "$NETWORK" in
  main) NET_DIR="$DATA_DIR" ;;
  test) NET_DIR="$DATA_DIR/testnet3" ;;
  regtest) NET_DIR="$DATA_DIR/regtest" ;;
esac

# Optional indexes. Unset leaves Nito Core's own default (all three are on
# in v4); 0 or 1 sets the option explicitly. Written above the network
# section so they apply whichever network is used.
INDEX_CONF=""
INDEXES_OFF=""
for pair in NITO_TXINDEX:txindex NITO_TRANSPARENTHISTORYINDEX:transparenthistoryindex NITO_ORCHARDINDEX:orchardindex; do
  var="${pair%%:*}"
  opt="${pair#*:}"
  # shellcheck disable=SC2154 # value is assigned by eval
  eval "value=\${$var:-}"
  case "$value" in
    "") ;;
    0|1)
      INDEX_CONF="${INDEX_CONF}${opt}=${value}
"
      if [ "$value" = "0" ]; then
        INDEXES_OFF="$INDEXES_OFF $var:$opt"
      fi
      ;;
    *) echo "Invalid $var: $value (expected 0 or 1, or unset for Nito Core's default)" >&2; exit 1 ;;
  esac
done

# Nito Core leaves a switched-off index's database on disk, so remove it.
# Turning the index back on later just rebuilds it. Only the environment
# variables above do this, not options passed to nitod as arguments.
for pair in $INDEXES_OFF; do
  var="${pair%%:*}"
  opt="${pair#*:}"
  dir="$NET_DIR/indexes/$opt"
  if [ -d "$dir" ]; then
    size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
    echo "nito-docker: $var=0, removing $dir (${size:-unknown size})"
    rm -rf "$dir"
  fi
done

CONF_FILE="$DATA_DIR/nito.conf"
{
  echo "server=1"
  # Node only. The official release binaries include the wallet (a source
  # build leaves it out, and accepts this option anyway); pass
  # -disablewallet=0 to the container to turn it on.
  echo "disablewallet=1"
  echo "rpcuser=${NITO_RPC_USER}"
  echo "rpcpassword=${NITO_RPC_PASSWORD}"
  [ "$NETWORK" = "test" ] && echo "testnet=1"
  [ "$NETWORK" = "regtest" ] && echo "regtest=1"
  printf '%s' "$INDEX_CONF"
  echo ""
  echo "$SECTION"
  echo "rpcbind=0.0.0.0"
  # RPC needs to be reachable from a separate dashboard container over the
  # compose network (unlike a same-process setup, which could stay
  # 127.0.0.1-only) - default is permissive for generic standalone use,
  # but callers on Umbrel should pass NITO_RPC_ALLOW_IP=${NETWORK_IP}/16
  # (Umbrel's own documented mechanism for exactly this: scoping an RPC
  # allowlist to its own app subnet rather than 0.0.0.0/0). Access is
  # still gated by the generated rpcuser/rpcpassword either way - this is
  # the same defense-in-depth shape the official Bitcoin/Lightning apps
  # already use for their own inter-app RPC reachability.
  echo "rpcallowip=${NITO_RPC_ALLOW_IP:-0.0.0.0/0}"
  echo "rpcport=${NITO_RPC_PORT:-8825}"
  echo "listen=1"
  echo "bind=0.0.0.0"
  echo "port=${NITO_P2P_PORT:-8820}"
} > "$CONF_FILE"

# Any arguments given to the container (e.g. Compose "command:") are passed
# on to nitod, so other options can be set without a new image.
exec gosu nito nitod -datadir="$DATA_DIR" -conf="$CONF_FILE" -printtoconsole "$@"
