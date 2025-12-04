#!/usr/bin/env bash
set -euo pipefail

# Build CryptoCore.xcframework from backend/libs/crypto-core

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
CRATE_DIR="$ROOT_DIR/backend/libs/crypto-core"
OUT_DIR="$(pwd)"
INC_DIR="$OUT_DIR/include"
FRAMEWORK_NAME="CryptoCore"

mkdir -p "$INC_DIR"

if ! command -v cbindgen >/dev/null 2>&1; then
  echo "cbindgen not found. Install with: cargo install cbindgen" >&2
  exit 1
fi

if [ ! -f "$CRATE_DIR/cbindgen.toml" ]; then
  echo "cbindgen.toml not found at $CRATE_DIR" >&2
  exit 1
fi

echo "Generating C header via cbindgen..."
cbindgen "$CRATE_DIR" -c "$CRATE_DIR/cbindgen.toml" -o "$INC_DIR/cryptocore.h"

echo "Building static libraries..."
targets=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
for t in "${targets[@]}"; do
  echo "  • Installing target $t..."
  rustup target add "$t" || true
  echo "  • Building for $t..."
  cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target "$t"
done

echo "Creating XCFramework..."
DEV_LIB="$ROOT_DIR/target/aarch64-apple-ios/release/libcrypto_core.a"
SIM_LIB_ARM="$ROOT_DIR/target/aarch64-apple-ios-sim/release/libcrypto_core.a"
SIM_LIB_X86="$ROOT_DIR/target/x86_64-apple-ios/release/libcrypto_core.a"

# Verify all libraries exist
for lib in "$DEV_LIB" "$SIM_LIB_ARM" "$SIM_LIB_X86"; do
  if [ ! -f "$lib" ]; then
    echo "Error: Static library not found: $lib" >&2
    exit 1
  fi
done

rm -rf "$FRAMEWORK_NAME.xcframework"
xcodebuild -create-xcframework \
  -library "$DEV_LIB" -headers "$INC_DIR" \
  -library "$SIM_LIB_ARM" -headers "$INC_DIR" \
  -library "$SIM_LIB_X86" -headers "$INC_DIR" \
  -output "$FRAMEWORK_NAME.xcframework"

if [ -d "$FRAMEWORK_NAME.xcframework" ]; then
  echo "✅ Built $FRAMEWORK_NAME.xcframework"
  echo ""
  echo "Framework location: $(pwd)/$FRAMEWORK_NAME.xcframework"
  echo "Header location: $INC_DIR/cryptocore.h"
  echo ""
  echo "To use in Xcode: Drag $FRAMEWORK_NAME.xcframework into your project"
else
  echo "❌ Failed to create XCFramework" >&2
  exit 1
fi

