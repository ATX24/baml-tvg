#!/usr/bin/env bash
# Run Swift integration tests with local dylib and OpenRouter key.
#
# Usage:
#   ./scripts/run-tests.sh [--filter <TestName>]
#
# Environment:
#   OPENROUTER_API_KEY  — required; your OpenRouter API key
#   BAML_LIBRARY_PATH   — optional; defaults to the local debug build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_DIR="$(cd "$SWIFT_DIR/.." && pwd)"

# Detect arch for local dylib path
ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
    TARGET_TRIPLE="aarch64-apple-darwin"
else
    TARGET_TRIPLE="x86_64-apple-darwin"
fi

# Default BAML_LIBRARY_PATH to local release build
: "${BAML_LIBRARY_PATH:="$ENGINE_DIR/target/$TARGET_TRIPLE/release/libbaml_cffi.dylib"}"

if [ ! -f "$BAML_LIBRARY_PATH" ]; then
    echo "ERROR: libbaml_cffi.dylib not found at $BAML_LIBRARY_PATH"
    echo "Build it first with:"
    echo "  cargo build --release --target $TARGET_TRIPLE -p baml_cffi"
    echo "Or set BAML_LIBRARY_PATH to point to your dylib."
    exit 1
fi

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo "WARNING: OPENROUTER_API_KEY not set — integration tests will be skipped."
fi

echo "==> BAML_LIBRARY_PATH=$BAML_LIBRARY_PATH"
echo "==> Running Swift tests..."

cd "$SWIFT_DIR"
BAML_LIBRARY_PATH="$BAML_LIBRARY_PATH" \
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
swift test "$@"
