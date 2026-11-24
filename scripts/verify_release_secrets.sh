#!/usr/bin/env bash
# Release ship guard: blocks TestFlight / App Store builds that still contain the
# committed placeholder secrets. Run at the top of the fastlane `beta` and `release`
# lanes and as a Release-only Run Script build phase on the app target.
#
# Escape hatch (exceptional local Release archives only, never for shipping):
#   SKIP_RELEASE_SECRETS_CHECK=1 bash scripts/verify_release_secrets.sh
#
# Exit 0: all checks pass. Exit 1: placeholder sentinel found; ship blocked.
#
# Sentinels must stay in sync with config/Secrets.xcconfig defaults and
# AppConfig.Placeholder in Swift.

set -euo pipefail

# ---------------------------------------------------------------------------
# Escape hatch
# ---------------------------------------------------------------------------
if [[ "${SKIP_RELEASE_SECRETS_CHECK:-}" == "1" ]]; then
  echo "warning: SKIP_RELEASE_SECRETS_CHECK=1 — release secrets check bypassed."
  echo "         Only use this for exceptional local Release archives, NOT for"
  echo "         TestFlight or App Store uploads."
  exit 0
fi

# ---------------------------------------------------------------------------
# Locate xcconfig files relative to this script (fastlane runs from fastlane/, Xcode
# from SRCROOT; SCRIPT_DIR/.. is the repo root in both cases).
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_XCCONFIG="${REPO_ROOT}/config/Secrets.xcconfig"
LOCAL_XCCONFIG="${REPO_ROOT}/config/Secrets.local.xcconfig"

# ---------------------------------------------------------------------------
# Helper: effective value of an xcconfig key. Local wins over base (matches
# #include? "Secrets.local.xcconfig"). Returns the raw value; $(DOUBLE_SLASH) is not expanded.
# ---------------------------------------------------------------------------
xcconfig_value() {
  local key="$1"
  local value=""
  # Base first, then local (local overrides)
  for file in "$BASE_XCCONFIG" "$LOCAL_XCCONFIG"; do
    [[ -f "$file" ]] || continue
    local match
    match=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | tail -1 || true)
    if [[ -n "$match" ]]; then
      # Strip key, =, surrounding whitespace, inline comments
      value="${match#*=}"
      value="${value%%//*}"  # strip inline // comment
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
    fi
  done
  echo "$value"
}

# ---------------------------------------------------------------------------
# Check each ship-critical value against its sentinel
# ---------------------------------------------------------------------------
ERRORS=""

MIXPANEL_PROD="$(xcconfig_value MIXPANEL_PROD_TOKEN)"
FEEDBACK="$(xcconfig_value FEEDBACK_EMAIL)"
PRIVACY="$(xcconfig_value PRIVACY_POLICY_URL)"

if [[ "$MIXPANEL_PROD" == "PLACEHOLDER_MIXPANEL_PROD_TOKEN" ]] || [[ -z "$MIXPANEL_PROD" ]]; then
  ERRORS="${ERRORS}  - MIXPANEL_PROD_TOKEN is still the clone default\n"
fi

if [[ "$FEEDBACK" == "noreply@example.com" ]] || [[ -z "$FEEDBACK" ]]; then
  ERRORS="${ERRORS}  - FEEDBACK_EMAIL is still noreply@example.com\n"
fi

# Raw PRIVACY_POLICY_URL looks like "https:$(DOUBLE_SLASH)example.com/privacy"; match the sentinel host.
if echo "$PRIVACY" | grep -q "example.com/privacy"; then
  ERRORS="${ERRORS}  - PRIVACY_POLICY_URL still points to example.com\n"
fi

if [[ ! -f "$LOCAL_XCCONFIG" ]]; then
  ERRORS="${ERRORS}  - config/Secrets.local.xcconfig is missing\n"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [[ -n "$ERRORS" ]]; then
  echo ""
  echo "error: Release ship check failed — placeholder secrets still active."
  printf "%b" "$ERRORS"
  echo ""
  echo "Copy config/Secrets.local.xcconfig.template → config/Secrets.local.xcconfig"
  echo "and fill in real values before shipping."
  echo "See CONTRIBUTING.md § Shipping to TestFlight / App Store."
  echo ""
  exit 1
fi

echo "verify_release_secrets: all checks passed."
