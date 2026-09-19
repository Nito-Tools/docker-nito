#!/bin/sh
set -eu

DATA_DIR="${NITO_DATA_DIR:-/data}"
mkdir -p "$DATA_DIR"

NETWORK="${NITO_NETWORK:-main}"
case "$NETWORK" in
  main) SECTION="[main]" ;;
  test) SECTION="[test]" ;;
  regtest) SECTION="[regtest]" ;;
  *) echo "Invalid NITO_NETWORK: $NETWORK (expected main, test, or regtest)" >&2; exit 1 ;;
esac

: "${NITO_RPC_USER:?NITO_RPC_USER is required}"
: "${NITO_RPC_PASSWORD:?NITO_RPC_PASSWORD is required}"

CONF_FILE="$DATA_DIR/nito.conf"
{
  echo "server=1"
  echo "rpcuser=${NITO_RPC_USER}"
  echo "rpcpassword=${NITO_RPC_PASSWORD}"
  [ "$NETWORK" = "test" ] && echo "testnet=1"
  [ "$NETWORK" = "regtest" ] && echo "regtest=1"
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

exec nitod -datadir="$DATA_DIR" -conf="$CONF_FILE" -printtoconsole
