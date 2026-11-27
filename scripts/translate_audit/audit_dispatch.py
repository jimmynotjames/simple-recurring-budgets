#!/usr/bin/env python3
"""
Render one audit prompt per locale from tmp/translate-audit-inputs/audit_source.json and
AUDIT_PROMPT_TEMPLATE.md into tmp/translate-audit-prompts/{L}.md, for `translation-audit-locale`.

Each prompt gets the translator's own regional note and glossary slice (both imported from
translate_catalog/dispatch_prompts.py) and one entry per key the locale has translated:
  flat:   {"english", "comment", "enChars", "current", "currentChars"}
  plural: {"englishPlural": {category: en}, "comment", "currentPlural": {category: current}}
The demo-content, plural and glossary sections render only when the slice needs them.
Unless --no-clean, deletes the dispatched locales' stale tmp/translate-audit-outputs/{L}.json.

Usage:
  python3 scripts/translate_audit/audit_dispatch.py [--no-clean] [locale ...]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIR = REPO_ROOT / "scripts" / "translate_catalog"
AUDIT_INPUTS_DIR = REPO_ROOT / "tmp" / "translate-audit-inputs"
PROMPTS_DIR = REPO_ROOT / "tmp" / "translate-audit-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "translate-audit-outputs"
SOURCE_PATH = AUDIT_INPUTS_DIR / "audit_source.json"
TEMPLATE_PATH = Path(__file__).parent / "AUDIT_PROMPT_TEMPLATE.md"

sys.path.insert(0, str(CATALOG_DIR))
from locales import LOCALES, LOCALE_NAMES  # noqa: E402
from dispatch_prompts import REGIONAL_NOTES, _GENERIC_NOTE, glossary_lines, is_transcreated  # noqa: E402
from prompt_render import compact_json, render  # noqa: E402
import app_config  # noqa: E402


def build_slice(locale: str, source: dict) -> dict:
    """Per-key audit input for one locale: English + current translation + char lengths.
    Plural keys carry per-category objects instead of flat strings + char counts."""
    out: dict[str, dict] = {}
    for key, entry in source.items():
        current = entry.get("translations", {}).get(locale)
        if not current:
            continue
        if "plural" in entry:
            out[key] = {
                "englishPlural": entry["plural"],
                "comment": entry.get("comment", ""),
                "currentPlural": current,
            }
            continue
        english = entry.get("value", "")
        out[key] = {
            "english": english,
            "comment": entry.get("comment", ""),
            "enChars": len(english),
            "current": current,
            "currentChars": len(current),
        }
    return out


def render_audit_prompt(template: str, locale: str, slice_source: dict) -> str:
    english = [
        text
        for entry in slice_source.values()
        for text in (entry["englishPlural"].values() if "englishPlural" in entry else [entry["english"]])
    ]
    glossary = glossary_lines(english, locale)
    sections = set()
    if any(is_transcreated(key) for key in slice_source):
        sections.add("sample")
    if any("englishPlural" in entry for entry in slice_source.values()):
        sections.add("plural")
    if glossary:
        sections.add("glossary")
    return render(
        template,
        {
            "LOCALE_NAME": LOCALE_NAMES.get(locale, locale),
            "LOCALE_CODE": locale,
            "REGIONAL_NOTE": REGIONAL_NOTES.get(locale, _GENERIC_NOTE),
            "GLOSSARY": glossary,
            "SOURCE_JSON": compact_json(slice_source),
        },
        sections,
        known={"sample", "plural", "glossary"},
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-clean", action="store_true", help="Do not delete pre-existing audit output files.")
    parser.add_argument("locales", nargs="*", help="Locales to dispatch (default: all with translations).")
    args = parser.parse_args(argv)

    if not SOURCE_PATH.exists():
        print(
            f"ERROR: {SOURCE_PATH} not found. Run `python3 scripts/translate_audit/audit_extract.py` first.",
            file=sys.stderr,
        )
        return 1

    with SOURCE_PATH.open(encoding="utf-8") as f:
        source: dict = json.load(f)
    template = app_config.load_template(TEMPLATE_PATH)

    requested = args.locales if args.locales else LOCALES
    unknown = [loc for loc in requested if loc not in LOCALES]
    if unknown:
        print(f"ERROR: not target locales: {unknown}", file=sys.stderr)
        return 2

    PROMPTS_DIR.mkdir(parents=True, exist_ok=True)
    for existing in PROMPTS_DIR.glob("*.md"):
        existing.unlink()

    written = 0
    dispatched_locales: list[str] = []
    for locale in sorted(requested):
        slice_source = build_slice(locale, source)
        if not slice_source:
            continue
        (PROMPTS_DIR / f"{locale}.md").write_text(render_audit_prompt(template, locale, slice_source), encoding="utf-8")
        dispatched_locales.append(locale)
        written += 1
        print(f"  Wrote {len(slice_source)} keys for {locale} → {PROMPTS_DIR / f'{locale}.md'}")

    # Clear stale outputs for the locales we're (re)dispatching, so a partial prior run
    # doesn't leave findings the report would double-count.
    if not args.no_clean and OUTPUTS_DIR.exists():
        cleaned = 0
        for locale in dispatched_locales:
            stale = OUTPUTS_DIR / f"{locale}.json"
            if stale.exists():
                stale.unlink()
                cleaned += 1
        if cleaned:
            print(f"Cleaned {cleaned} stale output file(s) from {OUTPUTS_DIR}")

    print(f"\n{written} audit prompt(s) written to {PROMPTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
