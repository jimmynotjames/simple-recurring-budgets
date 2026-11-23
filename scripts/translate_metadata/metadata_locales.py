"""
Single source of truth for the App Store *metadata* localization pipeline.

Metadata sibling of scripts/translate_catalog/locales.py. Both pipelines target the
SAME markets but use DIFFERENT locale code systems:

  * In-app strings (Localizable.xcstrings) use *runtime* BCP 47 codes (`ar`, `de`,
    `nb`, `nl`, `zh-Hans`, ...), defined in translate_catalog/locales.py.
  * App Store Connect metadata folders (fastlane/metadata/<storefront>/) use
    *storefront* codes, which differ for several markets (`ar-SA`, `de-DE`,
    `es-ES`, `fr-FR`, `no`, `nl-NL`, ...).

`deliver` / `upload_to_app_store` reads the storefront-coded folders, so this module
owns the runtime -> storefront mapping and metadata-specific facts (translatable
fields, character limits, brand constant, cultural register notes). The other
translate_metadata/ scripts import from here.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Human-readable locale names come from the in-app pipeline (single source of truth).
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "translate_catalog"))
from locales import LOCALE_NAMES, LOCALES as RUNTIME_LOCALES  # noqa: E402

# English source storefront; everything else is transcreated from it. Never a target.
SOURCE_LOCALE = "en-US"

# Brand token, verbatim in every locale (never translated, transliterated, or glossed).
# The App Store `name` is "Wren" + a transcreated descriptor.
BRAND = "Wren"

# In-app runtime locale -> App Store Connect storefront code (the exact folder names
# `deliver` expects under fastlane/metadata/). Identical codes map to themselves.
#
# IMPORTANT: several markets need a REGION-QUALIFIED storefront code though the runtime
# code is plain: bn->bn-BD, gu/kn/ml/mr/or/pa/ta/te->*-IN, sl->sl-SI, ur->ur-PK.
# `deliver`/ASC REJECTS the plain code ("Unsupported directory name(s)"). When adding a
# locale, don't assume runtime == storefront: confirm against the list `fastlane
# push_metadata` prints on an unknown folder (or ASC's locale list).
RUNTIME_TO_STOREFRONT: dict[str, str] = {
    "ar": "ar-SA",
    "bn": "bn-BD",
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
    "gu": "gu-IN",
    "he": "he",
    "hi": "hi",
    "hr": "hr",
    "hu": "hu",
    "id": "id",
    "it": "it",
    "ja": "ja",
    "kn": "kn-IN",
    "ko": "ko",
    "ml": "ml-IN",
    "mr": "mr-IN",
    "ms": "ms",
    "nb": "no",
    "nl": "nl-NL",
    "or": "or-IN",
    "pa": "pa-IN",
    "pl": "pl",
    "pt-BR": "pt-BR",
    "pt-PT": "pt-PT",
    "ro": "ro",
    "ru": "ru",
    "sk": "sk",
    "sl": "sl-SI",
    "sv": "sv",
    "ta": "ta-IN",
    "te": "te-IN",
    "th": "th",
    "tr": "tr",
    "uk": "uk",
    "ur": "ur-PK",
    "vi": "vi",
    "zh-Hans": "zh-Hans",
    "zh-Hant": "zh-Hant",
}

# Fail loud if the pipelines drift (e.g. a locale added in-app but not mapped here).
_unmapped = [loc for loc in RUNTIME_LOCALES if loc not in RUNTIME_TO_STOREFRONT]
if _unmapped:
    raise RuntimeError(
        f"RUNTIME_TO_STOREFRONT is missing runtime locale(s) present in "
        f"translate_catalog/locales.py: {_unmapped}"
    )

STOREFRONT_TO_RUNTIME: dict[str, str] = {v: k for k, v in RUNTIME_TO_STOREFRONT.items()}

# Target storefronts (sorted), excluding the en-US source.
STOREFRONT_LOCALES: list[str] = sorted(RUNTIME_TO_STOREFRONT.values())

# Human-readable name per storefront.
STOREFRONT_NAMES: dict[str, str] = {
    storefront: LOCALE_NAMES[runtime]
    for runtime, storefront in RUNTIME_TO_STOREFRONT.items()
}

# Transcreated fields with Apple's hard character limits (Unicode code points, not bytes).
FIELD_LIMITS: dict[str, int] = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "keywords": 100,
    "description": 4000,
    "release_notes": 4000,
}

# Ordered transcreated fields.
TRANSLATABLE_FIELDS: list[str] = [
    "name",
    "subtitle",
    "promotional_text",
    "keywords",
    "description",
    "release_notes",
]

# Per-locale fields copied verbatim from en-US (never sent to the model): URLs, the same
# for every storefront unless localized by hand.
PASSTHROUGH_FIELDS: list[str] = [
    "marketing_url",
    "privacy_url",
    "support_url",
]

# Catalog-level field (fastlane/metadata/copyright.txt), untouched by this pipeline.
SHARED_FIELDS: list[str] = [
    "copyright",
]

# Field-level guidance injected into every prompt: what each field is for and how to transcreate it.
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
