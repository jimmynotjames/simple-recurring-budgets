"""
Single source of truth for the App Store *screenshot demo-content* pipeline.

This pipeline generates the culturally-tuned, per-locale demo data that the app
is seeded with when capturing App Store marketing screenshots (≤3 budgets per
locale with realistic names, emoji, currency, and amounts). It is the screenshot
sibling of:

  * scripts/translate_catalog/  -> in-app UI strings (Localizable.xcstrings)
  * scripts/translate_metadata/ -> App Store text metadata (fastlane/metadata/)

It reuses the runtime<->storefront locale mapping owned by
scripts/translate_metadata/metadata_locales.py (do NOT duplicate that map). The
two code systems:

  * The per-locale subagent work is keyed by App Store Connect *storefront* codes
    (ar-SA, de-DE, no, nl-NL, ...), matching the metadata pipeline, so cultural
    notes and human-readable names line up 1:1 with metadata.
  * The merged demo-content *catalog* the UI test bundles is keyed by the app's
    *runtime* locale code (ar, de, nb, nl, ...) — i.e. the exact `-AppleLanguages`
    string fastlane `snapshot` launches the app with. `merge.py` maps storefront
    -> runtime when writing the catalog.

The English source (en-US) is authored by hand as SOURCE.json in this directory
and is the structure every locale transcreates from; it is also emitted verbatim
as the `en-US` catalog entry by `merge.py`.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Reuse the runtime<->storefront mapping + human-readable names from the metadata
# pipeline. Single source of truth — never re-list the locale set here.
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_metadata"))
from metadata_locales import (  # noqa: E402
    RUNTIME_TO_STOREFRONT,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    STOREFRONT_NAMES,
    STOREFRONT_TO_RUNTIME,
)

# Canonical English source structure + the directory holding it.
PIPELINE_DIR = Path(__file__).parent
SOURCE_JSON_PATH = PIPELINE_DIR / "SOURCE.json"
PROMPT_TEMPLATE_PATH = PIPELINE_DIR / "PROMPT_TEMPLATE.md"

# Transient pipeline I/O (gitignored under tmp/).
INPUTS_DIR = REPO_ROOT / "tmp" / "screenshot-content-inputs"
PROMPTS_DIR = REPO_ROOT / "tmp" / "screenshot-content-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "screenshot-content-outputs"

# The UI-test-bundled demo-content catalog (keyed by runtime locale code). Lives
# in the test target so the marketing fixtures never ship in the production app.
CATALOG_DIR = REPO_ROOT / "simple-recurring-budgetsUITests" / "ScreenshotSeeds"

# At most this many budgets per locale (the screen story stays glanceable).
MAX_BUDGETS = 3

# Budget "roles" carried through from SOURCE.json. `everyday-food` is mandatory
# (Food/Groceries is the universal anchor); the personal/feminine-leaning budget
# may be dropped or swapped by a locale if it does not fit.
REQUIRED_ROLES: set[str] = {"everyday-food"}

# Valid BudgetPeriod raw values (must match Domain/BudgetPeriod.swift).
VALID_PERIODS: set[str] = {"daily", "weekly", "biweekly", "monthly", "specificDates"}

# Default ISO-4217 currency per storefront. The subagent is told this is the
# expected currency for the market and should only deviate with a recorded
# `_questions` note. Values chosen as the dominant consumer currency of the
# storefront's primary market.
CURRENCY_BY_STOREFRONT: dict[str, str] = {
    "ar-SA": "SAR",
    "ca": "EUR",
    "cs": "CZK",
    "da": "DKK",
    "de-DE": "EUR",
    "el": "EUR",
    "en-AU": "AUD",
    "en-CA": "CAD",
    "en-GB": "GBP",
    "es-ES": "EUR",
    "es-MX": "MXN",
    "fi": "EUR",
    "fr-FR": "EUR",
    "fr-CA": "CAD",
    "he": "ILS",
    "hi": "INR",
    "hr": "EUR",
    "hu": "HUF",
    "id": "IDR",
    "it": "EUR",
    "ja": "JPY",
    "ko": "KRW",
    "ms": "MYR",
    "nl-NL": "EUR",
    "no": "NOK",
    "pl": "PLN",
    "pt-BR": "BRL",
    "pt-PT": "EUR",
    "ro": "RON",
    "ru": "RUB",
    "sk": "EUR",
    "sv": "SEK",
    "th": "THB",
    "tr": "TRY",
    "uk": "UAH",
    "vi": "VND",
    "zh-Hans": "CNY",
    "zh-Hant": "TWD",
}
# The en-US source currency.
CURRENCY_BY_STOREFRONT[SOURCE_LOCALE] = "USD"

# ISO-4217 currencies that have NO minor unit (amounts are whole numbers). Used
# by validate.py to reject e.g. "2500.50" JPY, and told to the subagent so it
# writes whole-number amounts for these markets.
ZERO_DECIMAL_CURRENCIES: set[str] = {
    "JPY",
    "KRW",
    "VND",
    "IDR",
    "HUF",
    "CLP",
    "ISK",
}


def currency_decimals(currency_code: str) -> int:
    """Return the number of decimal places permitted for a currency (0 or 2)."""
    return 0 if currency_code.upper() in ZERO_DECIMAL_CURRENCIES else 2


def runtime_for_storefront(storefront: str) -> str:
    """Map a storefront code to the app runtime code the catalog is keyed by."""
    if storefront == SOURCE_LOCALE:
        return SOURCE_LOCALE
    return STOREFRONT_TO_RUNTIME[storefront]


__all__ = [
    "REPO_ROOT",
    "PIPELINE_DIR",
    "SOURCE_JSON_PATH",
    "PROMPT_TEMPLATE_PATH",
    "INPUTS_DIR",
    "PROMPTS_DIR",
    "OUTPUTS_DIR",
    "CATALOG_DIR",
    "MAX_BUDGETS",
    "REQUIRED_ROLES",
    "VALID_PERIODS",
    "CURRENCY_BY_STOREFRONT",
    "ZERO_DECIMAL_CURRENCIES",
    "currency_decimals",
    "runtime_for_storefront",
    # re-exported from metadata_locales for convenience
    "RUNTIME_TO_STOREFRONT",
    "STOREFRONT_TO_RUNTIME",
    "STOREFRONT_LOCALES",
    "STOREFRONT_NAMES",
    "SOURCE_LOCALE",
]
