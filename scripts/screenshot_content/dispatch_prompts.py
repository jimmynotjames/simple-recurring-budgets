#!/usr/bin/env python3
"""
Compose one ready-to-dispatch demo-content prompt per target storefront.

For each storefront in tmp/screenshot-content-inputs/manifest.json, writes
  tmp/screenshot-content-prompts/{storefront}.md
by substituting PROMPT_TEMPLATE.md's placeholders ({LOCALE_NAME}, {LOCALE_CODE},
{RUNTIME_CODE}, {CURRENCY}, {CURRENCY_DECIMALS}, {CULTURAL_NOTE}, {SOURCE_JSON}).

The parent agent then reads each {storefront}.md and dispatches one
screenshot-content-locale subagent per storefront, which writes its output JSON
to tmp/screenshot-content-outputs/{storefront}.json.

By default also clears any pre-existing output JSON for the manifest storefronts
so subagents start clean. Pass --no-clean to preserve them.

Usage:
  python3 scripts/screenshot_content/dispatch_prompts.py [--no-clean]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from content_locales import (  # noqa: E402
    CURRENCY_BY_STOREFRONT,
    INPUTS_DIR,
    OUTPUTS_DIR,
    PROMPT_TEMPLATE_PATH,
    PROMPTS_DIR,
    STOREFRONT_NAMES,
    currency_decimals,
    runtime_for_storefront,
)

# Reuse the metadata pipeline's per-storefront cultural register notes verbatim —
# the formality/voice guidance is identical work, single-sourced there.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "translate_metadata"))
from dispatch_prompts import CULTURAL_NOTES, _GENERIC_NOTE  # noqa: E402

SOURCE_PATH = INPUTS_DIR / "source.json"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-clean", action="store_true", help="Do not delete pre-existing output JSON files.")
    args = parser.parse_args(argv)

    if not SOURCE_PATH.exists() or not MANIFEST_PATH.exists():
        print("ERROR: run `python3 scripts/screenshot_content/extract.py [--missing]` first.", file=sys.stderr)
        return 1

    source = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    manifest: list[str] = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    template = PROMPT_TEMPLATE_PATH.read_text(encoding="utf-8")

    if not manifest:
        print("Manifest is empty — no prompts to write.")
        return 0

    PROMPTS_DIR.mkdir(parents=True, exist_ok=True)
    for existing in PROMPTS_DIR.glob("*.md"):
        existing.unlink()

    if not args.no_clean and OUTPUTS_DIR.exists():
        cleaned = 0
        for storefront in manifest:
            stale = OUTPUTS_DIR / f"{storefront}.json"
            if stale.exists():
                stale.unlink()
                cleaned += 1
        if cleaned:
            print(f"Cleaned {cleaned} stale output file(s) from {OUTPUTS_DIR}")

    source_json = json.dumps(source, ensure_ascii=False, indent=2)
    for storefront in sorted(manifest):
        currency = CURRENCY_BY_STOREFRONT.get(storefront, "USD")
        prompt = (
            template.replace("{LOCALE_NAME}", STOREFRONT_NAMES.get(storefront, storefront))
            .replace("{LOCALE_CODE}", storefront)
            .replace("{RUNTIME_CODE}", runtime_for_storefront(storefront))
            .replace("{CURRENCY_DECIMALS}", str(currency_decimals(currency)))
            .replace("{CURRENCY}", currency)
            .replace("{CULTURAL_NOTE}", CULTURAL_NOTES.get(storefront, _GENERIC_NOTE))
            .replace("{SOURCE_JSON}", source_json)
        )
        (PROMPTS_DIR / f"{storefront}.md").write_text(prompt, encoding="utf-8")

    print(f"{len(manifest)} prompt file(s) written to {PROMPTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
