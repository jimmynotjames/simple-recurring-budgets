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
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
INPUTS_DIR = REPO_ROOT / "tmp" / "translate-inputs"
PROMPTS_DIR = REPO_ROOT / "tmp" / "translate-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "translate-outputs"
SOURCE_PATH = INPUTS_DIR / "source.json"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"
TEMPLATE_PATH = Path(__file__).parent / "PROMPT_TEMPLATE.md"

sys.path.insert(0, str(Path(__file__).parent))
from locales import LOCALE_NAMES  # noqa: E402

# Regional/dialect notes inlined into the prompt for locales where it
# materially helps the model pick the right register or script variant.
REGIONAL_NOTES: dict[str, str] = {
    "en-AU": "Use Australian English spelling (e.g. \"organise\", \"colour\").",
    "en-CA": "Use Canadian English spelling (mostly British: \"colour\", \"centre\").",
    "en-GB": "Use British English spelling (e.g. \"organise\", \"colour\", \"centre\").",
    "es-MX": "Use Latin American Spanish vocabulary and \"tú\" rather than \"vosotros\".",
    "fr-CA": "Use Canadian French conventions and vocabulary where they differ from France French.",
    "pt-BR": "Use Brazilian Portuguese vocabulary and orthography.",
    "pt-PT": "Use European Portuguese vocabulary and orthography.",
    "zh-Hans": "Use Simplified Chinese characters (mainland China conventions).",
    "zh-Hant": "Use Traditional Chinese characters (Taiwan conventions).",
}


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
        slice_source = {k: source[k] for k in keys if k in source}
        if not slice_source:
            continue
        locale_name = LOCALE_NAMES.get(locale, locale)
        regional_note = REGIONAL_NOTES.get(locale, "")
        prompt = (
            template.replace("{LOCALE_NAME}", locale_name)
            .replace("{LOCALE_CODE}", locale)
            .replace("{REGIONAL_NOTE}", regional_note)
            .replace("{SOURCE_JSON}", json.dumps(slice_source, ensure_ascii=False, indent=2, sort_keys=True))
        )
        out_path = PROMPTS_DIR / f"{locale}.md"
        out_path.write_text(prompt, encoding="utf-8")
        print(f"  Wrote {len(slice_source)} keys for {locale} → {out_path}")

    print(f"\n{len(manifest)} prompt file(s) written to {PROMPTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
