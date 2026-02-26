#!/usr/bin/env bash
# stamp-distribution-package.sh
#
# Substitutes BAML_VERSION and BAML_SPM_CHECKSUM placeholders in
# Package.distribution.swift and writes the result to Package.swift.
#
# Usage (called by CI when pushing to the baml-swift mirror repo):
#   scripts/stamp-distribution-package.sh <version> <spm_checksum>
#
# Example:
#   scripts/stamp-distribution-package.sh 0.219.0 abc123def456...

set -euo pipefail

VERSION="${1:?Usage: $0 <version> <spm_checksum>}"
CHECKSUM="${2:?Usage: $0 <version> <spm_checksum>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_PKG="$SCRIPT_DIR/../Package.distribution.swift"
OUT_PKG="$SCRIPT_DIR/../Package.swift"

if [[ ! -f "$DIST_PKG" ]]; then
    echo "Error: Package.distribution.swift not found at $DIST_PKG" >&2
    exit 1
fi

sed \
    -e "s/BAML_VERSION/$VERSION/g" \
    -e "s/BAML_SPM_CHECKSUM/$CHECKSUM/g" \
    "$DIST_PKG" > "$OUT_PKG"

echo "Stamped Package.swift:"
echo "  version  : $VERSION"
echo "  checksum : $CHECKSUM"
echo "  output   : $OUT_PKG"
