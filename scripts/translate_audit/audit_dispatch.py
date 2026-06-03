#!/usr/bin/env python3
"""
Compose one ready-to-dispatch audit prompt per locale, from
tmp/translate-audit-inputs/audit_source.json + AUDIT_PROMPT_TEMPLATE.md.

For each target locale L (that has at least one translation in audit_source.json),
writes tmp/translate-audit-prompts/{L}.md with {LOCALE_NAME}, {LOCALE_CODE},
{REGIONAL_NOTE}, and {SOURCE_JSON} substituted. The SOURCE_JSON slice for L contains,
per key, the English value + comment + the current L translation + both char lengths:

  { "<key>": { "english", "comment", "enChars", "current", "currentChars" }, ... }

Mirrors scripts/translate_catalog/dispatch_prompts.py, and reuses that pipeline's
LOCALES / LOCALE_NAMES and the REGIONAL_NOTES / _GENERIC_NOTE register-cultural notes
via import (no duplication) — so the auditor grades against the same per-locale rubric
the translator was given.

The parent agent then reads each {locale}.md and dispatches one `translation-audit-locale`
subagent per locale; subagents write findings JSON to tmp/translate-audit-outputs/{locale}.json.

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
from dispatch_prompts import REGIONAL_NOTES, _GENERIC_NOTE, build_glossary_block  # noqa: E402


def build_slice(locale: str, source: dict) -> dict:
    """Per-key audit input for one locale: English + current translation + char lengths."""
    out: dict[str, dict] = {}
    for key, entry in source.items():
        current = entry.get("translations", {}).get(locale)
        if not current:
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
    template = TEMPLATE_PATH.read_text(encoding="utf-8")

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
        regional_note = REGIONAL_NOTES.get(locale, _GENERIC_NOTE)
        glossary_block = build_glossary_block(
            [e.get("english", "") for e in slice_source.values()], locale, LOCALE_NAMES.get(locale, locale)
        )
        prompt = (
            template.replace("{LOCALE_NAME}", LOCALE_NAMES.get(locale, locale))
            .replace("{LOCALE_CODE}", locale)
            .replace("{REGIONAL_NOTE}", regional_note)
            .replace("{GLOSSARY}", glossary_block)
            .replace("{SOURCE_JSON}", json.dumps(slice_source, ensure_ascii=False, indent=2, sort_keys=True))
        )
        (PROMPTS_DIR / f"{locale}.md").write_text(prompt, encoding="utf-8")
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
