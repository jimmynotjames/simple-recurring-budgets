#!/usr/bin/env bash
# Bare compile step: no tests, generic destination, never boots a simulator.
# ARCHS=arm64 is a build-speed choice, not correctness (a generic destination otherwise
# compiles every source twice); to build x86_64 drop ARCHS=arm64 but keep ONLY_ACTIVE_ARCH=NO.
# Signing is deliberately the project default: CODE_SIGNING_ALLOWED=NO skips the
# simulated .xcent, and CKContainer.default() then raises an uncatchable ObjC CKException.
# translate_catalog/sync_catalog.py reads this build's derived data; keep its STRINGSDATA_DIR in step.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

exec xcodebuild build \
    -project simple-recurring-budgets.xcodeproj \
    -scheme simple-recurring-budgets \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/DerivedData \
    -quiet \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO
