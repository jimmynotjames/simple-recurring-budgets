#!/usr/bin/env python3
"""
Render one translation prompt per locale from tmp/translate-inputs/{source,manifest}.json.

UI keys go to tmp/translate-prompts/{L}.md (PROMPT_TEMPLATE.md, `translation-locale`);
`sample.*` keys go to {L}.sample.md (SAMPLE_PROMPT_TEMPLATE.md, `sample-content-locale`).
Each prompt gets the locale's regional note, its glossary slice, and only the keys it needs;
the plural and glossary sections render only when the slice has a plural or a glossary match.
Unless --no-clean, deletes that locale's stale tmp/translate-outputs/{L}.json and
{L}.sample.json first, so validate --subset never sees a prior run's keys.

Usage: python3 scripts/translate_catalog/dispatch_prompts.py [--no-clean]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
INPUTS_DIR = REPO_ROOT / "tmp" / "translate-inputs"
PROMPTS_DIR = REPO_ROOT / "tmp" / "translate-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "translate-outputs"
SOURCE_PATH = INPUTS_DIR / "source.json"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"
TEMPLATE_PATH = Path(__file__).parent / "PROMPT_TEMPLATE.md"
SAMPLE_TEMPLATE_PATH = Path(__file__).parent / "SAMPLE_PROMPT_TEMPLATE.md"

sys.path.insert(0, str(Path(__file__).parent))
import app_config  # noqa: E402

GLOSSARY_PATH = app_config.GLOSSARY_PATH

# Demo-content key prefixes (i18n/app.json `transcreatedNamespaces`), transcreated by their own
# agent and template; none means the app has no demo-content stream.
TRANSCREATED_NAMESPACES: tuple[str, ...] = app_config.TRANSCREATED_NAMESPACES


def is_transcreated(key: str) -> bool:
    return bool(TRANSCREATED_NAMESPACES) and key.startswith(TRANSCREATED_NAMESPACES)


from locales import LOCALE_NAMES  # noqa: E402
from prompt_render import compact_json, render  # noqa: E402

# The exact CLDR categories each locale needs, injected per plural entry so the model never
# recalls them from memory. plural_rules.py imports nothing, so this cross-package import is safe.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "translate_audit"))
try:
    from plural_rules import PLURAL_RULES  # noqa: E402
except Exception:
    PLURAL_RULES = {}  # the template then falls back to "the categories the locale needs"

_GLOSSARY_CACHE: dict | None = None


def load_glossary() -> dict:
    """Load glossary.json once; tolerate absence (returns empty terms)."""
    global _GLOSSARY_CACHE
    if _GLOSSARY_CACHE is None:
        if GLOSSARY_PATH.exists():
            with GLOSSARY_PATH.open(encoding="utf-8") as f:
                _GLOSSARY_CACHE = json.load(f)
        else:
            _GLOSSARY_CACHE = {"terms": {}}
    return _GLOSSARY_CACHE


def glossary_lines(values, locale: str) -> str:
    """Bullet list of the agreed `locale` rendering of every glossary term that appears
    (whole word or phrase, singular or a regular -s/-es plural) in any English `values`; ""
    when none match, which drops the template's glossary section. audit_dispatch.py uses it
    too. The plural matters: a string that only says "checklists" still needs "Checklist"."""
    terms = load_glossary().get("terms", {})
    haystack = "\n".join(values)
    matched: list[tuple[str, str]] = []
    for term_en in sorted(terms, key=lambda t: (-len(t), t.casefold())):  # longest-first
        translation = terms[term_en].get("translations", {}).get(locale)
        if translation and re.search(rf"\b{re.escape(term_en)}(?:e?s)?\b", haystack, flags=re.IGNORECASE):
            matched.append((term_en, translation))
    return "\n".join(f'- "{en}" → "{tr}"' for en, tr in matched)


def english_values(entry: dict) -> list[str]:
    """The English text of a flat (`value`) or plural (`plural`) source entry."""
    if entry.get("plural"):
        return list(entry["plural"].values())
    return [entry.get("value", "")]


def render_prompt(template: str, locale: str, stream_source: dict) -> str:
    glossary = glossary_lines([v for e in stream_source.values() for v in english_values(e)], locale)
    sections = {"plural"} if any("plural" in e for e in stream_source.values()) else set()
    if glossary:
        sections.add("glossary")
    return render(
        template,
        {
            "LOCALE_NAME": LOCALE_NAMES.get(locale, locale),
            "LOCALE_CODE": locale,
            "REGIONAL_NOTE": REGIONAL_NOTES.get(locale, _GENERIC_NOTE),
            "GLOSSARY": glossary,
            "SOURCE_JSON": compact_json(stream_source),
        },
        sections,
        known={"plural", "glossary"},
    )


def prompt_entry(entry: dict, locale: str) -> dict:
    """A source.json entry as the translator sees it."""
    out = {k: v for k, v in entry.items() if k != "formatSpecifiers"}
    out["enChars"] = len(entry.get("value") or (entry.get("plural") or {}).get("other", ""))
    if entry.get("plural"):
        required = PLURAL_RULES.get(locale, {}).get("required")
        if required:
            out["requiredPluralCategories"] = required
    return out


# UI register, dialect and script notes live in i18n/regional_notes.json; the store-listing
# CULTURAL_NOTES are kept apart on purpose. The registry's `register` field holds each locale's
# formality call, and test_locale_registry checks both note maps state it.
REGIONAL_NOTES: dict[str, str] = app_config.REGIONAL_NOTES
_GENERIC_NOTE: str = app_config.GENERIC_REGIONAL_NOTE

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Do not delete pre-existing tmp/translate-outputs/{locale}.json files.",
    )
    args = parser.parse_args(argv)

    if not SOURCE_PATH.exists() or not MANIFEST_PATH.exists():
        print(
            "ERROR: missing source.json or manifest.json. "
            "Run `python3 scripts/translate_catalog/extract.py --missing` first.",
            file=sys.stderr,
        )
        return 1

    with SOURCE_PATH.open(encoding="utf-8") as f:
        source: dict = json.load(f)
    with MANIFEST_PATH.open(encoding="utf-8") as f:
        manifest: dict[str, list[str]] = json.load(f)
    template = app_config.load_template(TEMPLATE_PATH)
    sample_template = app_config.load_template(SAMPLE_TEMPLATE_PATH) if TRANSCREATED_NAMESPACES else ""

    if not manifest:
        print("Manifest is empty — no prompts to write.")
        return 0

    PROMPTS_DIR.mkdir(parents=True, exist_ok=True)
    # Clear stale prompt files so we don't accidentally dispatch yesterday's work.
    for existing in PROMPTS_DIR.glob("*.md"):
        existing.unlink()

    # Clear stale per-locale output files for the locales we're about to dispatch,
    # so subagents start from a clean slate and validate --subset doesn't trip on
    # leftover keys from a prior run on a different branch.
    if not args.no_clean and OUTPUTS_DIR.exists():
        cleaned = 0
        for locale in manifest:
            for stale in (OUTPUTS_DIR / f"{locale}.json", OUTPUTS_DIR / f"{locale}.sample.json"):
                if stale.exists():
                    stale.unlink()
                    cleaned += 1
        if cleaned:
            print(f"Cleaned {cleaned} stale output file(s) from {OUTPUTS_DIR}")

    ui_files = sample_files = 0
    for locale in sorted(manifest):
        slice_source = {k: prompt_entry(source[k], locale) for k in manifest[locale] if k in source}
        streams = (
            (template, "", {k: v for k, v in slice_source.items() if not is_transcreated(k)}),
            (sample_template, ".sample", {k: v for k, v in slice_source.items() if is_transcreated(k)}),
        )
        for stream_template, suffix, stream_source in streams:
            if not stream_source:
                continue
            out_path = PROMPTS_DIR / f"{locale}{suffix}.md"
            out_path.write_text(render_prompt(stream_template, locale, stream_source), encoding="utf-8")
            print(f"  Wrote {len(stream_source)} keys for {locale} → {out_path}")
            if suffix:
                sample_files += 1
            else:
                ui_files += 1

    print(
        f"\n{ui_files} UI prompt file(s) (translation-locale) and {sample_files} sample prompt file(s) "
        f"(sample-content-locale) written to {PROMPTS_DIR}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
