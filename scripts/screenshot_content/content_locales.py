"""
Single source of truth for the App Store *screenshot demo-content* pipeline.

Generates the culturally-tuned, per-locale demo data the app is seeded with when
capturing App Store marketing screenshots (≤3 budgets per locale with realistic
names, emoji, currency, amounts). Sibling of:

  * scripts/translate_catalog/  -> in-app UI strings (Localizable.xcstrings)
  * scripts/translate_metadata/ -> App Store text metadata (fastlane/metadata/)

Reuses the runtime<->storefront mapping from
scripts/translate_metadata/metadata_locales.py (don't duplicate it). Two code systems:

  * Per-locale subagent work is keyed by App Store Connect *storefront* codes
    (ar-SA, de-DE, no, nl-NL, ...), matching the metadata pipeline.
  * The merged catalog the UI test bundles is keyed by the app's *runtime*
    locale code (ar, de, nb, nl, ...), the exact `-AppleLanguages` string
    fastlane `snapshot` launches with. `merge.py` maps storefront -> runtime.

The English source (en-US) is hand-authored as SOURCE.json in this directory;
every locale transcreates from its structure, and `merge.py` emits it verbatim
as the `en-US` catalog entry.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Runtime<->storefront mapping and names come from the metadata pipeline; never re-list locales here.
sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_metadata"))
from metadata_locales import (  # noqa: E402
    RUNTIME_TO_STOREFRONT,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    STOREFRONT_NAMES,
    STOREFRONT_TO_RUNTIME,
)

# Canonical English source structure.
PIPELINE_DIR = Path(__file__).parent
SOURCE_JSON_PATH = PIPELINE_DIR / "SOURCE.json"
PROMPT_TEMPLATE_PATH = PIPELINE_DIR / "PROMPT_TEMPLATE.md"

# Transient pipeline I/O (gitignored under tmp/).
INPUTS_DIR = REPO_ROOT / "tmp" / "screenshot-content-inputs"
PROMPTS_DIR = REPO_ROOT / "tmp" / "screenshot-content-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "screenshot-content-outputs"

# UI-test-bundled catalog (keyed by runtime locale code); in the test target so
# marketing fixtures never ship in the app.
CATALOG_DIR = REPO_ROOT / "simple-recurring-budgetsUITests" / "ScreenshotSeeds"

# Max budgets per locale (keeps the screen story glanceable).
MAX_BUDGETS = 3

# Budget "roles" from SOURCE.json. `everyday-food` is mandatory (universal anchor);
# the personal/feminine-leaning budget may be dropped or swapped if it doesn't fit.
REQUIRED_ROLES: set[str] = {"everyday-food"}

# Valid BudgetPeriod raw values (must match Domain/BudgetPeriod.swift).
VALID_PERIODS: set[str] = {"daily", "weekly", "biweekly", "monthly", "specificDates"}

# Default ISO-4217 currency per storefront (dominant consumer currency of its primary
# market). Subagents deviate only with a recorded `_questions` note.
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

# Region-qualified storefronts (see metadata_locales): India locales use INR, plus
# Bangladesh (BDT), Pakistan (PKR), Slovenia (EUR).
CURRENCY_BY_STOREFRONT.update(
    {
        "bn-BD": "BDT",
        "gu-IN": "INR",
        "kn-IN": "INR",
        "ml-IN": "INR",
        "mr-IN": "INR",
        "or-IN": "INR",
        "pa-IN": "INR",
        "sl-SI": "EUR",
        "ta-IN": "INR",
        "te-IN": "INR",
        "ur-PK": "PKR",
    }
)

# ISO-3166 region per storefront: the market whose currency/number formatting the
# screenshots render (its locale must resolve to the CURRENCY_BY_STOREFRONT currency;
# keep the two 1:1). Drives `-AppleLocale` via `primary_locale_for_storefront()`:
# fastlane `snapshot` only sets `-AppleLanguages`, so language-only locales (de, ja,
# nb, …) are region-less, `Locale.currency` is nil, and the Settings currency example
# falls back to USD even though seeded budgets show the right currency.
REGION_BY_STOREFRONT: dict[str, str] = {
    "ar-SA": "SA",
    "bn-BD": "BD",
    "ca": "ES",
    "cs": "CZ",
    "da": "DK",
    "de-DE": "DE",
    "el": "GR",
    "en-AU": "AU",
    "en-CA": "CA",
    "en-GB": "GB",
    "es-ES": "ES",
    "es-MX": "MX",
    "fi": "FI",
    "fr-CA": "CA",
    "fr-FR": "FR",
    "gu-IN": "IN",
    "he": "IL",
    "hi": "IN",
    "hr": "HR",
    "hu": "HU",
    "id": "ID",
    "it": "IT",
    "ja": "JP",
    "kn-IN": "IN",
    "ko": "KR",
    "ml-IN": "IN",
    "mr-IN": "IN",
    "ms": "MY",
    "nl-NL": "NL",
    "no": "NO",
    "or-IN": "IN",
    "pa-IN": "IN",
    "pl": "PL",
    "pt-BR": "BR",
    "pt-PT": "PT",
    "ro": "RO",
    "ru": "RU",
    "sk": "SK",
    "sl-SI": "SI",
    "sv": "SE",
    "ta-IN": "IN",
    "te-IN": "IN",
    "th": "TH",
    "tr": "TR",
    "uk": "UA",
    "ur-PK": "PK",
    "vi": "VN",
    "zh-Hans": "CN",
    "zh-Hant": "TW",
}
# The en-US source region.
REGION_BY_STOREFRONT[SOURCE_LOCALE] = "US"

# ISO-4217 currencies with no minor unit (whole-number amounts). validate.py uses
# it to reject e.g. "2500.50" JPY; subagents are told the same.
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


def primary_locale_for_storefront(storefront: str) -> str:
    """Return the ICU locale identifier the screenshots launch this storefront with.

    Runtime locale code + the storefront's region:
      de-DE  -> de_DE      (region appended to a language-only runtime)
      no     -> nb_NO      (runtime `nb`, region NO)
      zh-Hans-> zh_Hans_CN (script kept, region appended)
      pt-BR  -> pt_BR      (runtime already region-qualified; left as-is)

    Passed as `-AppleLocale` so `Locale.autoupdatingCurrent.currency` and number/date
    formatting match the market.
    """
    region = REGION_BY_STOREFRONT[storefront]
    base = runtime_for_storefront(storefront).replace("-", "_")
    suffix = f"_{region}"
    return base if base.endswith(suffix) else f"{base}{suffix}"


def primary_locale_for_runtime(runtime: str) -> str:
    """Same as `primary_locale_for_storefront`, keyed by the runtime locale code."""
    if runtime == SOURCE_LOCALE:
        return primary_locale_for_storefront(SOURCE_LOCALE)
    return primary_locale_for_storefront(RUNTIME_TO_STOREFRONT[runtime])


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
    "REGION_BY_STOREFRONT",
    "ZERO_DECIMAL_CURRENCIES",
    "currency_decimals",
    "runtime_for_storefront",
    "primary_locale_for_storefront",
    "primary_locale_for_runtime",
    # re-exported from metadata_locales
    "RUNTIME_TO_STOREFRONT",
    "STOREFRONT_TO_RUNTIME",
    "STOREFRONT_LOCALES",
    "STOREFRONT_NAMES",
    "SOURCE_LOCALE",
]
