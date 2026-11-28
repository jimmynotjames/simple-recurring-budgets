#!/usr/bin/env python3
"""
Render one transcreation prompt per storefront from tmp/metadata-inputs/{source,manifest}.json
into tmp/metadata-prompts/{S}.md, for `metadata-locale`.

Each prompt gets the storefront's CULTURAL_NOTES entry and only the fields it needs, each with
its English value, limit (`byteLimit` for keywords, else `charLimit`) and FIELD_GUIDANCE; the
subtitle, keywords and longer-field sections render only when the slice has those fields.
Unless --no-clean, deletes the storefronts' stale tmp/metadata-outputs/{S}.json first.

Usage: python3 scripts/translate_metadata/dispatch_prompts.py [--no-clean]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METADATA_DIR = REPO_ROOT / "fastlane" / "metadata"
INPUTS_DIR = REPO_ROOT / "tmp" / "metadata-inputs"
PROMPTS_DIR = REPO_ROOT / "tmp" / "metadata-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "metadata-outputs"
SOURCE_PATH = INPUTS_DIR / "source.json"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"
TEMPLATE_PATH = Path(__file__).parent / "PROMPT_TEMPLATE.md"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import (  # noqa: E402
    STOREFRONT_TO_RUNTIME,
    FIELD_BYTE_LIMITS,
    FIELD_GUIDANCE,
    STOREFRONT_NAMES,
    glossary_lines,
    store_field,
    store_name,
)
from prompt_render import compact_json, render  # noqa: E402  (translate_catalog; metadata_locales puts it on the path)
import app_config  # noqa: E402
from locales import register_line  # noqa: E402

PROSE_FIELDS = {"promotional_text", "description", "release_notes"}

# A line of a bulleted list in the English description ("• Easy setup", "- Easy setup").
_BULLET_RE = re.compile(r"^\s*[•\-*·]\s")

# Marketing register, positioning and keyword notes live in i18n/cultural_notes.json, kept apart
# from the in-app REGIONAL_NOTES on purpose; the registry's `register` field holds each locale's
# formality call, and the prompt states it through register_line(), so the notes don't.
CULTURAL_NOTES: dict[str, str] = app_config.CULTURAL_NOTES
_GENERIC_NOTE: str = app_config.GENERIC_CULTURAL_NOTE


def build_prompt_source(slice_fields: list[str], source: dict) -> dict:
    """Annotate each needed field with its English value, limit, and guidance."""
    out: dict[str, dict] = {}
    for field in slice_fields:
        if field not in source:
            continue
        limit_key = "byteLimit" if field in FIELD_BYTE_LIMITS else "charLimit"
        out[field] = {
            "english": source[field]["value"],
            limit_key: source[field]["charLimit"],
            "guidance": FIELD_GUIDANCE.get(field, ""),
        }
    return out


def render_prompt(template: str, storefront: str, prompt_source: dict) -> str:
    sections = {field for field in ("name", "subtitle", "keywords") if field in prompt_source}
    if any(_BULLET_RE.match(line) for line in prompt_source.get("description", {}).get("english", "").splitlines()):
        sections.add("bullets")
    if PROSE_FIELDS & prompt_source.keys():
        sections.add("prose")
    glossary = glossary_lines(storefront)
    if glossary:
        sections.add("glossary")
    # A keywords-only run must still know the subtitle's words, which share the search index.
    current_subtitle = "" if "subtitle" in prompt_source else store_field(METADATA_DIR, storefront, "subtitle")
    if "keywords" in prompt_source and current_subtitle:
        sections.add("current_subtitle")
    register = register_line(STOREFRONT_TO_RUNTIME.get(storefront, storefront))
    if register:
        sections.add("register")
    return render(
        template,
        {
            "LOCALE_NAME": STOREFRONT_NAMES.get(storefront, storefront),
            "LOCALE_CODE": storefront,
            "REGISTER": register,
            "CULTURAL_NOTE": CULTURAL_NOTES.get(storefront, _GENERIC_NOTE),
            "SOURCE_JSON": compact_json(prompt_source),
            "STORE_NAME": store_name(METADATA_DIR, storefront),
            "GLOSSARY": glossary,
            "CURRENT_SUBTITLE": current_subtitle,
        },
        sections,
        known={"name", "subtitle", "keywords", "current_subtitle", "prose", "bullets", "glossary", "register"},
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Do not delete pre-existing tmp/metadata-outputs/{storefront}.json files.",
    )
    args = parser.parse_args(argv)

    if not SOURCE_PATH.exists() or not MANIFEST_PATH.exists():
        print(
            "ERROR: missing source.json or manifest.json. "
            "Run `python3 scripts/translate_metadata/extract.py --missing` first.",
            file=sys.stderr,
        )
        return 1

    with SOURCE_PATH.open(encoding="utf-8") as f:
        source: dict = json.load(f)
    with MANIFEST_PATH.open(encoding="utf-8") as f:
        manifest: dict[str, list[str]] = json.load(f)
    template = app_config.load_template(TEMPLATE_PATH)

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

    for storefront in sorted(manifest):
        slice_fields = manifest[storefront]
        prompt_source = build_prompt_source(slice_fields, source)
        if not prompt_source:
            continue
        prompt = render_prompt(template, storefront, prompt_source)
        out_path = PROMPTS_DIR / f"{storefront}.md"
        out_path.write_text(prompt, encoding="utf-8")
        print(f"  Wrote {len(prompt_source)} field(s) for {storefront} → {out_path}")

    print(f"\n{len(manifest)} prompt file(s) written to {PROMPTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
