"""
Single source of truth for the App Store *metadata* localization pipeline.

This is the metadata sibling of scripts/translate_catalog/locales.py. The two
pipelines target the SAME set of markets, but use DIFFERENT locale code systems:

  * In-app strings (Localizable.xcstrings) use the app's *runtime* BCP 47 codes
    (`ar`, `de`, `nb`, `nl`, `zh-Hans`, ...). Those live in translate_catalog/locales.py.
  * App Store Connect *metadata* folders (fastlane/metadata/<storefront>/) use
    App Store Connect *storefront* codes, which differ for several markets
    (`ar-SA`, `de-DE`, `es-ES`, `fr-FR`, `no`, `nl-NL`, ...).

`deliver` / `upload_to_app_store` reads the storefront-coded folders, so this
module owns the runtime -> storefront mapping and all metadata-specific facts
(translatable fields, character limits, the brand constant, cultural register
notes). Import from here in the other translate_metadata/ scripts.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Reuse the human-readable locale names from the in-app pipeline so we keep a
# single source of truth for "what does this code mean in English".
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "translate_catalog"))
from locales import LOCALE_NAMES, LOCALES as RUNTIME_LOCALES  # noqa: E402

# The English source storefront. Its folder holds the copy everything else is
# transcreated from. It is never itself a translation target.
SOURCE_LOCALE = "en-US"

# Brand token. Kept verbatim in every locale (never translated, transliterated,
# or glossed). The App Store `name` is "Wren" + a transcreated descriptor.
BRAND = "Wren"

# Map each in-app runtime locale to its App Store Connect storefront code.
# Codes that are identical in both systems map to themselves. The values are the
# exact folder names `deliver` expects under fastlane/metadata/.
RUNTIME_TO_STOREFRONT: dict[str, str] = {
    "ar": "ar-SA",
    "bn": "bn",
    "ca": "ca",
    "cs": "cs",
    "da": "da",
    "de": "de-DE",
    "el": "el",
    "en-AU": "en-AU",
    "en-CA": "en-CA",
    "en-GB": "en-GB",
    "es": "es-ES",
    "es-MX": "es-MX",
    "fi": "fi",
    "fr": "fr-FR",
    "fr-CA": "fr-CA",
    "gu": "gu",
    "he": "he",
    "hi": "hi",
    "hr": "hr",
    "hu": "hu",
    "id": "id",
    "it": "it",
    "ja": "ja",
    "kn": "kn",
    "ko": "ko",
    "ml": "ml",
    "mr": "mr",
    "ms": "ms",
    "nb": "no",
    "nl": "nl-NL",
    "or": "or",
    "pa": "pa",
    "pl": "pl",
    "pt-BR": "pt-BR",
    "pt-PT": "pt-PT",
    "ro": "ro",
    "ru": "ru",
    "sk": "sk",
    "sl": "sl",
    "sv": "sv",
    "ta": "ta",
    "te": "te",
    "th": "th",
    "tr": "tr",
    "uk": "uk",
    "ur": "ur",
    "vi": "vi",
    "zh-Hans": "zh-Hans",
    "zh-Hant": "zh-Hant",
}

# Fail loud if the two pipelines ever drift apart (e.g. a locale added to the
# in-app set but not mapped here).
_unmapped = [loc for loc in RUNTIME_LOCALES if loc not in RUNTIME_TO_STOREFRONT]
if _unmapped:
    raise RuntimeError(
        f"RUNTIME_TO_STOREFRONT is missing runtime locale(s) present in "
        f"translate_catalog/locales.py: {_unmapped}"
    )

STOREFRONT_TO_RUNTIME: dict[str, str] = {v: k for k, v in RUNTIME_TO_STOREFRONT.items()}

# The translation TARGET storefronts (sorted), excluding the en-US source.
STOREFRONT_LOCALES: list[str] = sorted(RUNTIME_TO_STOREFRONT.values())

# Human-readable name per storefront, derived from the in-app name map.
STOREFRONT_NAMES: dict[str, str] = {
    storefront: LOCALE_NAMES[runtime]
    for runtime, storefront in RUNTIME_TO_STOREFRONT.items()
}

# Fields we transcreate, with Apple's hard character limit for each. Character
# counts are Unicode code points (App Store Connect counts characters, not bytes).
FIELD_LIMITS: dict[str, int] = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "keywords": 100,
    "description": 4000,
    "release_notes": 4000,
}

# Ordered list of the fields the pipeline transcreates.
TRANSLATABLE_FIELDS: list[str] = [
    "name",
    "subtitle",
    "promotional_text",
    "keywords",
    "description",
    "release_notes",
]

# Per-locale fields that are copied verbatim from en-US (never sent to the model).
# These are URLs: same destination for every storefront unless you localize them
# by hand later.
PASSTHROUGH_FIELDS: list[str] = [
    "marketing_url",
    "privacy_url",
    "support_url",
]

# Catalog-level (not per-locale) field. Lives at fastlane/metadata/copyright.txt
# and is left untouched by this pipeline.
SHARED_FIELDS: list[str] = [
    "copyright",
]

# Static, field-level guidance injected into every prompt. Explains what each
# field is for and how to transcreate it (not just translate).
FIELD_GUIDANCE: dict[str, str] = {
    "name": (
        f'App name shown on the store. MUST begin with the brand "{BRAND}" '
        "followed by a short, localized descriptor (e.g. \"Wren – Daily Expense "
        "Tracker\"). Keep \"" + BRAND + "\" verbatim; transcreate only the "
        "descriptor. If the natural descriptor will not fit, shorten it — never "
        "drop the brand and never exceed the limit."
    ),
    "subtitle": (
        "Short tagline shown under the name. Punchy and benefit-driven, not a "
        "literal translation of the English. Title-case/sentence-case per local "
        "convention."
    ),
    "promotional_text": (
        "Short promotional banner (editable without a new app version). Lead with "
        "the most compelling, current hook."
    ),
    "keywords": (
        "Comma-separated SEARCH terms a native user would actually type to find a "
        "budgeting / expense app in this market. This is search behaviour, NOT a "
        "literal translation. Rules: no spaces after commas (they waste the "
        "limit); deduplicate; do NOT repeat words already used in name or "
        "subtitle (Apple indexes those separately); singular forms are usually "
        "enough. Fill as much of the limit as natural terms allow."
    ),
    "description": (
        "Full listing description. Transcreate persuasively into natural, native "
        "marketing prose — adapt idioms and flow, do not calque the English. "
        "Preserve the overall structure and line breaks (paragraphs, the bulleted "
        "feature list, the closing line)."
    ),
    "release_notes": (
        "The \"What's New\" text shown on the update sheet. Match the tone of the "
        "English; keep it warm and concise."
    ),
}
