#!/usr/bin/env python3
"""
Compose ready-to-dispatch translation prompts for each locale, one file per
locale, by combining PROMPT_TEMPLATE.md with the manifest written by
`extract.py --missing`.

For each locale L in tmp/translate-inputs/manifest.json, writes
  tmp/translate-prompts/{L}.md
containing the template with {LOCALE_NAME}, {LOCALE_CODE}, {REGIONAL_NOTE},
and {SOURCE_JSON} substituted. The SOURCE_JSON slice contains only the keys
that locale actually needs.

Usage:
  python3 scripts/translate_catalog/dispatch_prompts.py [--no-clean]

By default, also deletes any pre-existing tmp/translate-outputs/{locale}.json
files for the locales in the manifest, so subagents start from a clean slate
and validate.py --subset doesn't trip on leftover keys from prior runs. Pass
--no-clean to preserve those files (rare — generally only useful if you are
manually iterating on a single locale).

The parent agent then reads each {locale}.md and dispatches one subagent per
locale with that prompt as the input. Subagents write their output JSON to
tmp/translate-outputs/{locale}.json.
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
GLOSSARY_PATH = Path(__file__).parent / "glossary.json"

sys.path.insert(0, str(Path(__file__).parent))
from locale_register import GENERIC_REGISTER, REGISTER, compose_note  # noqa: E402
from locales import LOCALES, LOCALE_NAMES  # noqa: E402

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


def build_glossary_block(values, locale: str, locale_name: str | None = None) -> str:
    """Render a Markdown glossary block of the agreed `locale` translations for every glossary
    term that appears (whole-word / phrase) in any of the given English `values`. Returns "" when
    the glossary is empty or no term matches, so the {GLOSSARY} placeholder collapses cleanly.

    Importable so audit_dispatch.py injects the identical block (no duplication).
    """
    terms = load_glossary().get("terms", {})
    if not terms:
        return ""
    haystack = "\n".join(values)
    matched: list[tuple[str, str]] = []
    for term_en in sorted(terms, key=lambda t: (-len(t), t.casefold())):  # longest-first
        entry = terms[term_en]
        translation = entry.get("translations", {}).get(locale)
        if not translation:
            continue
        if re.search(rf"\b{re.escape(term_en)}\b", haystack, flags=re.IGNORECASE):
            matched.append((term_en, translation))
    if not matched:
        return ""
    name = locale_name or locale
    lines = [
        f"## Glossary — agreed {name} translations (rule 6: use these for consistency)",
        "",
        "Reuse these for the matching terms (incl. as parts of a longer string); keep the full "
        "string natural and coherent.",
        "",
    ]
    lines += [f'- "{en}" → "{tr}"' for en, tr in matched]
    return "\n".join(lines)

# UI-copy prefixes / addenda keyed by runtime locale. The register core lives in
# locale_register.REGISTER; these are catalog-specific (tone prefix, RTL layout,
# length discipline, script conventions) and must not restate formality rules.
_UI_PREFIXES: dict[str, str] = {
    "cs": "Modern ",
    "el": "Modern ",
    "fi": "Direct, natural ",
    "hr": "Modern ",
    "hu": "Modern ",
    "id": "Friendly, casual ",
    "ms": "Friendly, natural ",
    "ro": "Modern ",
    "sk": "Modern ",
    "uk": "Modern ",
    "vi": "Friendly, natural ",
}
_UI_ADDENDA: dict[str, str] = {
    "ar": (
        'Right-to-left: keep punctuation and any Latin tokens (e.g. "iCloud") '
        "correctly placed for RTL."
    ),
    "cs": "The informal address is standard for consumer apps.",
    "de": (
        "German typically runs longer than English — keep compounds tight so labels "
        "don't overflow."
    ),
    "fi": "Finnish runs long — keep UI labels tight.",
    "he": (
        'Right-to-left: keep punctuation and any Latin tokens (e.g. "iCloud") '
        "correctly placed for RTL. Friendly register."
    ),
    "hu": "Hungarian runs long — keep labels tight.",
    "ja": (
        "Use katakana for loanwords (e.g. アプリ). The English em-dash habit does not "
        "translate — restructure instead."
    ),
    "th": "Follow normal Thai spacing conventions.",
}

# Composed per-locale notes for the in-app translation / audit pipelines.
REGIONAL_NOTES: dict[str, str] = {
    locale: compose_note(
        REGISTER[locale],
        _UI_ADDENDA.get(locale, ""),
        prefix=_UI_PREFIXES.get(locale, ""),
    )
    for locale in LOCALES
}

# Fallback for any locale without a REGISTER entry: still steer register.
_GENERIC_NOTE = (
    "Write as a native speaker would for a modern consumer app: natural, idiomatic, "
    f"never calqued. Register: {GENERIC_REGISTER}"
)


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
    template = TEMPLATE_PATH.read_text(encoding="utf-8")

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
            stale = OUTPUTS_DIR / f"{locale}.json"
            if stale.exists():
                stale.unlink()
                cleaned += 1
        if cleaned:
            print(f"Cleaned {cleaned} stale output file(s) from {OUTPUTS_DIR}")

    for locale in sorted(manifest):
        keys = manifest[locale]
        # Annotate each entry with `enChars` (English character length) as a soft
        # length budget the subagent aims at — see the length rule in PROMPT_TEMPLATE.md.
        slice_source = {}
        for k in keys:
            if k not in source:
                continue
            entry = dict(source[k])
            # Length budget: flat keys use `value`; plural keys use the `other` form.
            ref = entry.get("value") or (entry.get("plural", {}) or {}).get("other", "")
            entry["enChars"] = len(ref)
            slice_source[k] = entry
        if not slice_source:
            continue
        locale_name = LOCALE_NAMES.get(locale, locale)
        regional_note = REGIONAL_NOTES.get(locale, _GENERIC_NOTE)
        gloss_values: list[str] = []
        for e in slice_source.values():
            if e.get("value"):
                gloss_values.append(e["value"])
            elif e.get("plural"):
                gloss_values.extend(e["plural"].values())
        glossary_block = build_glossary_block(gloss_values, locale, locale_name)
        prompt = (
            template.replace("{LOCALE_NAME}", locale_name)
            .replace("{LOCALE_CODE}", locale)
            .replace("{REGIONAL_NOTE}", regional_note)
            .replace("{GLOSSARY}", glossary_block)
            .replace("{SOURCE_JSON}", json.dumps(slice_source, ensure_ascii=False, indent=2, sort_keys=True))
        )
        out_path = PROMPTS_DIR / f"{locale}.md"
        out_path.write_text(prompt, encoding="utf-8")
        print(f"  Wrote {len(slice_source)} keys for {locale} → {out_path}")

    print(f"\n{len(manifest)} prompt file(s) written to {PROMPTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
