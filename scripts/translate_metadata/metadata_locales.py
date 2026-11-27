"""
Single source of truth for the App Store *metadata* localization pipeline.

This is the metadata sibling of scripts/translate_catalog/locales.py. Both target the
SAME markets, but use DIFFERENT locale code systems:

  * In-app strings (Localizable.xcstrings) use the app's *runtime* BCP 47 codes
    (`ar`, `de`, `nb`, `zh-Hans`, …).
  * App Store Connect *metadata* folders (fastlane/metadata/<storefront>/) use ASC
    *storefront* codes, which differ for several markets (`ar-SA`, `de-DE`, `no`,
    `nl-NL`, …). `deliver` reads the storefront-coded folders.

Both code systems, and the mapping between them, come from the locale registry in
fastlane/screenshot-config.json via locales.py — this module adds only the
metadata-specific facts (which fields are transcreated, their limits), read from i18n/app.json.

**Field limits are imported from scripts/appstore_metadata.py**, the validator that
actually gates the upload, so there is exactly one statement of Apple's limits in the
repo. Note `keywords` is limited in UTF-8 BYTES, not characters — a CJK or Indic
keyword list reaches the cap at roughly a third of the character count.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))
sys.path.insert(0, str(REPO_ROOT / "scripts"))
from locales import (  # noqa: E402
    LOCALE_NAMES,
    RUNTIME_TO_STOREFRONT,
    STOREFRONT_TO_RUNTIME,
)
from appstore_metadata import FIELD_BY_FILENAME  # noqa: E402
import app_config  # noqa: E402

_METADATA: dict = app_config.APP["metadata"]

# The English source storefront. Its folder holds the copy everything else is
# transcreated from. It is never itself a translation target.
SOURCE_LOCALE = "en-US"

# The translation TARGET storefronts (sorted), excluding the en-US source.
STOREFRONT_LOCALES: list[str] = sorted(
    storefront for storefront in RUNTIME_TO_STOREFRONT.values() if storefront != SOURCE_LOCALE
)

# Human-readable name per storefront, derived from the registry's names.
STOREFRONT_NAMES: dict[str, str] = {
    storefront: LOCALE_NAMES[runtime]
    for runtime, storefront in RUNTIME_TO_STOREFRONT.items()
}


def _limit(field: str, attribute: str) -> int | None:
    return getattr(FIELD_BY_FILENAME[f"{field}.txt"], attribute)


# Apple's hard limits, taken from the shipping validator. Character counts are Unicode
# code points; the byte map below is what actually binds for `keywords`.
FIELD_LIMITS: dict[str, int] = {
    field: _limit(field, "max_characters")
    for field in ("name", "subtitle", "promotional_text", "description", "release_notes")
    if _limit(field, "max_characters") is not None
}
FIELD_BYTE_LIMITS: dict[str, int] = {
    field: _limit(field, "max_utf8_bytes")
    for field in ("keywords",)
    if _limit(field, "max_utf8_bytes") is not None
}
# `keywords` is byte-limited, so give it a character entry only as a loose upper bound
# for prompts and reports that want one number.
FIELD_LIMITS.setdefault("keywords", FIELD_BYTE_LIMITS["keywords"])

# How the store `name` is handled (i18n/app.json `metadata.nameMode`):
#   "passthrough"  the name is the bare brand, copied from en-US (PASSTHROUGH_OVERRIDES lists the
#                  storefronts that must author it themselves);
#   "descriptor"   the name is "<brand> – <descriptor>", and the descriptor is transcreated.
NAME_MODE: str = _METADATA.get("nameMode", "passthrough")
if NAME_MODE not in ("passthrough", "descriptor"):
    raise RuntimeError(f"i18n/app.json: metadata.nameMode must be passthrough or descriptor, not {NAME_MODE!r}")

# Fields the pipeline transcreates, in order; "name" joins them first in descriptor mode.
TRANSLATABLE_FIELDS: list[str] = (["name"] if NAME_MODE == "descriptor" else []) + list(_METADATA["translatableFields"])

# Copied verbatim from en-US, never sent to a model.
PASSTHROUGH_FIELDS: list[str] = [f for f in _METADATA["passthroughFields"] if f not in TRANSLATABLE_FIELDS]

# Passthrough fields a storefront authors itself instead of copying from en-US; merge.py leaves
# these files alone (for example, a storefront where App Store Connect rejects the bare brand).
PASSTHROUGH_OVERRIDES: dict[str, frozenset[str]] = {
    storefront: frozenset(fields) for storefront, fields in _METADATA.get("passthroughOverrides", {}).items()
}

# In-app glossary terms the listing must render the same way the app does (i18n/app.json
# `metadata.glossaryTerms`). Pin core domain nouns only: UI verbs would straitjacket marketing prose.
METADATA_GLOSSARY_TERMS: tuple[str, ...] = tuple(_METADATA.get("glossaryTerms", ()))

GLOSSARY_PATH = app_config.GLOSSARY_PATH


def glossary_terms(storefront: str, glossary_path: Path = GLOSSARY_PATH) -> list[tuple[str, str]]:
    """(English, agreed translation) for each METADATA_GLOSSARY_TERMS entry the in-app glossary
    translates for this storefront's runtime locale; [] when there are none."""
    if not glossary_path.exists():
        return []
    terms = json.loads(glossary_path.read_text(encoding="utf-8")).get("terms", {})
    runtime = STOREFRONT_TO_RUNTIME.get(storefront, storefront)
    pairs: list[tuple[str, str]] = []
    for term in METADATA_GLOSSARY_TERMS:
        translation = terms.get(term, {}).get("translations", {}).get(runtime)
        if translation:
            pairs.append((term, translation))
    return pairs


def glossary_lines(storefront: str, glossary_path: Path = GLOSSARY_PATH) -> str:
    """Bullet list of glossary_terms() for a prompt; "" drops the template's glossary section."""
    return "\n".join(f'- "{en}" → "{tr}"' for en, tr in glossary_terms(storefront, glossary_path))


def store_field(metadata_dir: Path, storefront: str, field: str) -> str:
    """The storefront's committed value for `field`: its own file, else en-US's."""
    for locale in (storefront, SOURCE_LOCALE):
        path = metadata_dir / locale / f"{field}.txt"
        if path.exists() and path.read_text(encoding="utf-8").strip():
            return path.read_text(encoding="utf-8").strip()
    return ""


def store_name(metadata_dir: Path, storefront: str) -> str:
    """The storefront's App Store name: its own `name.txt`, else en-US's."""
    return store_field(metadata_dir, storefront, "name")

# Field-level guidance injected into every prompt (i18n/app.json `metadata.fieldGuidance`):
# what each field is for and how to transcreate it, rather than translate it.
FIELD_GUIDANCE: dict[str, str] = dict(_METADATA["fieldGuidance"])
