#!/usr/bin/env bash
# Build pulse-wallet-core as a static lib and vendor it into the macOS app.
# Run after changing anything in core/. Produces a universal (arm64+x86_64) lib
# so the app links on both Apple-silicon and Intel Macs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
VENDOR="$ROOT/apps/macos/Vendor"
LIB=libpulse_wallet_core.a

cd "$CORE"

echo "▸ building $LIB (release)…"
ARCHS=()
if rustup target list --installed | grep -q aarch64-apple-darwin; then
  cargo build --release --target aarch64-apple-darwin
  ARCHS+=("target/aarch64-apple-darwin/release/$LIB")
fi
if rustup target list --installed | grep -q x86_64-apple-darwin; then
  cargo build --release --target x86_64-apple-darwin
  ARCHS+=("target/x86_64-apple-darwin/release/$LIB")
fi

mkdir -p "$VENDOR"
if [ "${#ARCHS[@]}" -ge 2 ]; then
  echo "▸ lipo → universal"
  lipo -create "${ARCHS[@]}" -output "$VENDOR/$LIB"
elif [ "${#ARCHS[@]}" -eq 1 ]; then
  cp "${ARCHS[0]}" "$VENDOR/$LIB"
else
  echo "▸ no per-arch target installed; using host build"
  cargo build --release
  cp "target/release/$LIB" "$VENDOR/$LIB"
fi

echo "▸ vendored: $VENDOR/$LIB"
lipo -info "$VENDOR/$LIB" 2>/dev/null || true
