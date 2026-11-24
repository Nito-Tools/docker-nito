#!/usr/bin/env bash
# Check Nito Core's official Linux release files before this image uses them.
#
#   scripts/verify-nito-core-release.sh TAG [SHA256_AMD64 SHA256_ARM64]
#
# For release TAG (e.g. v4.1.0) it downloads SHA256SUMS, its Minisign
# signature and the x86_64 and aarch64 Linux tarballs, then checks:
#
#   1. SHA256SUMS is signed by Nito Core's release key, pinned in this repo
#      as nito-core-release.pub (copied from Nito Core's
#      contrib/release/nito-core-release.pub). A new key means a person
#      has to review and replace that file.
#   2. Both tarballs match SHA256SUMS.
#   3. Both tarballs have a GitHub build attestation from Nito Core's own
#      release workflow (build-release.yml in NitoNetwork/Nito-core), so
#      they were built by GitHub Actions, not uploaded by hand.
#   4. If SHA256_AMD64 and SHA256_ARM64 are given (the values pinned in the
#      Dockerfile), the tarballs match them too.
#
# Prints "amd64=<sha256>" and "arm64=<sha256>" on success; exits non-zero
# on any failure. Needs curl, sha256sum, minisign and gh (with GH_TOKEN).
set -euo pipefail

UPSTREAM=NitoNetwork/Nito-core
SIGNER_WORKFLOW="$UPSTREAM/.github/workflows/build-release.yml"
here="$(cd "$(dirname "$0")/.." && pwd)"
key="$here/nito-core-release.pub"

tag="${1:?usage: $0 TAG [SHA256_AMD64 SHA256_ARM64]}"
want_amd64="${2:-}"
want_arm64="${3:-}"
version="${tag#v}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

base="https://github.com/$UPSTREAM/releases/download/$tag"
for f in SHA256SUMS SHA256SUMS.minisig \
         "nito-$version-x86_64-linux-gnu.tar.gz" "nito-$version-aarch64-linux-gnu.tar.gz"; do
  curl -fsSL --retry 3 -o "$f" "$base/$f"
done

echo "1. Minisign signature on SHA256SUMS" >&2
minisign -Vm SHA256SUMS -x SHA256SUMS.minisig -p "$key" >&2

echo "2. Tarballs match SHA256SUMS" >&2
grep -E "  nito-$version-(x86_64|aarch64)-linux-gnu\.tar\.gz\$" SHA256SUMS > linux.sums
[ "$(wc -l < linux.sums)" = 2 ] || { echo "SHA256SUMS doesn't list both Linux tarballs" >&2; exit 1; }
sha256sum -c linux.sums >&2

echo "3. GitHub build attestations" >&2
for f in "nito-$version-x86_64-linux-gnu.tar.gz" "nito-$version-aarch64-linux-gnu.tar.gz"; do
  gh attestation verify "$f" --repo "$UPSTREAM" --signer-workflow "$SIGNER_WORKFLOW" >&2
  echo "$f: attestation OK" >&2
done

amd64="$(awk -v f="nito-$version-x86_64-linux-gnu.tar.gz" '$2 == f { print $1 }' linux.sums)"
arm64="$(awk -v f="nito-$version-aarch64-linux-gnu.tar.gz" '$2 == f { print $1 }' linux.sums)"

if [ -n "$want_amd64" ] || [ -n "$want_arm64" ]; then
  echo "4. Tarballs match the checksums pinned in the Dockerfile" >&2
  [ "$amd64" = "$want_amd64" ] || { echo "amd64: release has $amd64, Dockerfile pins $want_amd64" >&2; exit 1; }
  [ "$arm64" = "$want_arm64" ] || { echo "arm64: release has $arm64, Dockerfile pins $want_arm64" >&2; exit 1; }
  echo "Both match." >&2
fi

echo "amd64=$amd64"
echo "arm64=$arm64"
