#!/usr/bin/env bash
# One-time (or repeat-safe) machine setup: Homebrew CLI tools, Python 3 for
# scripts/test.sh, Xcode CLI, Lefthook hooks. Hooks use Lefthook, not Python pre-commit.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
	die "This project targets iOS; run system-setup on macOS with Xcode."
fi

if ! command -v brew >/dev/null 2>&1; then
	die "Homebrew not found. Install from https://brew.sh then re-run: make system"
fi

printf '%s\n' "==> Installing lefthook, swiftlint, swiftformat, gitleaks (brew; idempotent)"
brew install lefthook swiftlint swiftformat gitleaks

if ! command -v python3 >/dev/null 2>&1; then
	die "python3 not on PATH. Install Xcode Command Line Tools or: brew install python@3.12"
fi
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
	die "python3 must be 3.9 or newer (scripts/test.sh). Try: brew install python@3.12"
fi

if ! xcodebuild -version >/dev/null 2>&1; then
	die "xcodebuild not available. Install Xcode from the App Store, open it once, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi
printf '%s\n' "==> Xcode: $(xcodebuild -version | head -1)"

if ! xcrun simctl list runtimes 2>/dev/null | grep -qi 'iOS'; then
	printf '%s\n' "warning: no iOS Simulator runtime found in simctl output; install an iOS runtime in Xcode (Xcode > Settings > Platforms) if builds/tests fail." >&2
fi

printf '%s\n' "==> Installing Git hooks (lefthook)"
lefthook install

printf '\n%s\n' "Done. Next: make test   make lint"
printf '%s\n' "(OpenSpec CLI is optional for spec workflow; not installed by this script.)"
