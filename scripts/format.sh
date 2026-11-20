#!/usr/bin/env bash
# scripts/format.sh — run Apple's swift-format over Packages/ and App/
#
# swift-format ships with Xcode 15+ as `swift format` (note: subcommand, not
# hyphenated binary). No third-party install required.
#
# Usage:
#   scripts/format.sh          # format in place
#   scripts/format.sh --lint   # exit non-zero on diffs (for CI)

set -euo pipefail

cd "$(dirname "$0")/.."

SUBCOMMAND=(format --in-place --recursive)
if [[ "${1:-}" == "--lint" ]]; then
    SUBCOMMAND=(format lint --strict --recursive)
fi

exec swift "${SUBCOMMAND[@]}" \
    --configuration .swift-format \
    Packages App
