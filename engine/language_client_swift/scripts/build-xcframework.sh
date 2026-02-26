#!/usr/bin/env bash
set -euo pipefail

# Build script for BamlCFFI.xcframework
# Cross-compiles libbaml_cffi.a for all Apple targets and packages as XCFramework.
#
# Usage:
#   ./scripts/build-xcframework.sh [--release]
#
# The resulting XCFramework is placed in the current directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/../../" && pwd)"
CFFI_DIR="$ENGINE_DIR/language_client_cffi"
SWIFT_DIR="$ENGINE_DIR/language_client_swift"
TARGET_DIR="$ENGINE_DIR/target"

PROFILE="${1:---release}"
if [ "$PROFILE" = "--release" ]; then
    PROFILE_DIR="release"
    CARGO_FLAGS="--release"
else
    PROFILE_DIR="debug"
    CARGO_FLAGS=""
fi

echo "==> Building baml_cffi for Apple targets ($PROFILE_DIR)..."

# iOS targets
TARGETS=(
    "aarch64-apple-ios"
    "aarch64-apple-ios-sim"
    "x86_64-apple-ios"
    "aarch64-apple-darwin"
    "x86_64-apple-darwin"
)

# Install targets if missing
echo "==> Ensuring Rust targets are installed..."
for target in "${TARGETS[@]}"; do
    rustup target add "$target" 2>/dev/null || true
done

# Cross-compile for each target
for target in "${TARGETS[@]}"; do
    echo "==> Building for $target..."
    cargo build $CARGO_FLAGS --target "$target" -p baml_cffi --manifest-path "$CFFI_DIR/Cargo.toml"
done

# Create fat libraries (simulator = arm64 + x86_64)
echo "==> Creating fat libraries..."
mkdir -p "$TARGET_DIR/ios-simulator-fat" "$TARGET_DIR/macos-fat"

lipo -create \
    "$TARGET_DIR/aarch64-apple-ios-sim/$PROFILE_DIR/libbaml_cffi.a" \
    "$TARGET_DIR/x86_64-apple-ios/$PROFILE_DIR/libbaml_cffi.a" \
    -output "$TARGET_DIR/ios-simulator-fat/libbaml_cffi.a"

lipo -create \
    "$TARGET_DIR/aarch64-apple-darwin/$PROFILE_DIR/libbaml_cffi.a" \
    "$TARGET_DIR/x86_64-apple-darwin/$PROFILE_DIR/libbaml_cffi.a" \
    -output "$TARGET_DIR/macos-fat/libbaml_cffi.a"

# Prepare headers
echo "==> Preparing headers..."
HEADERS_DIR="$SWIFT_DIR/include"
if [ ! -f "$HEADERS_DIR/baml_cffi_generated.h" ]; then
    echo "ERROR: C header not found at $HEADERS_DIR/baml_cffi_generated.h"
    echo "Run 'cargo build' in language_client_cffi first to generate the header."
    exit 1
fi

# Remove old XCFramework
rm -rf "$SWIFT_DIR/BamlCFFI.xcframework"

# Create XCFramework
echo "==> Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$TARGET_DIR/aarch64-apple-ios/$PROFILE_DIR/libbaml_cffi.a" \
    -headers "$HEADERS_DIR/" \
    -library "$TARGET_DIR/ios-simulator-fat/libbaml_cffi.a" \
    -headers "$HEADERS_DIR/" \
    -library "$TARGET_DIR/macos-fat/libbaml_cffi.a" \
    -headers "$HEADERS_DIR/" \
    -output "$SWIFT_DIR/BamlCFFI.xcframework"

echo "==> XCFramework created at $SWIFT_DIR/BamlCFFI.xcframework"

# Zip for SPM distribution
echo "==> Zipping for SPM..."
cd "$SWIFT_DIR"
rm -f BamlCFFI.xcframework.zip
zip -r BamlCFFI.xcframework.zip BamlCFFI.xcframework

# Compute SPM checksum
if command -v swift &>/dev/null; then
    CHECKSUM=$(swift package compute-checksum BamlCFFI.xcframework.zip)
    echo "==> SPM checksum: $CHECKSUM"
    echo "$CHECKSUM" > BamlCFFI.xcframework.zip.sha256
fi

echo "==> Done!"
