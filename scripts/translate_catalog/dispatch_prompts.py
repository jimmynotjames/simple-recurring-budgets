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
from locales import LOCALE_NAMES  # noqa: E402

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

# Per-locale register/dialect/cultural notes inlined into the prompt where they
# materially help the model pick the right formality register, script variant, or
# culturally-appropriate phrasing. Ported and adapted (UI copy, not marketing) from
# the per-storefront CULTURAL_NOTES in scripts/translate_metadata/dispatch_prompts.py;
# storefront codes are remapped to this catalog's locale codes (see locales.py).
REGIONAL_NOTES: dict[str, str] = {
    "ar": "Modern Standard Arabic (MSA), not a regional dialect — MSA addresses all audiences with the same standard forms, so there is no casual/formal toggle; get a warm, contemporary feel through fresh, light phrasing. Right-to-left: keep punctuation and any Latin tokens (e.g. \"iCloud\") correctly placed for RTL.",
    "ca": "Natural, friendly Catalan as used in Apple's Catalan UI.",
    "cs": "Modern Czech app tone; natural phrasing over literal calques. The informal address is standard for consumer apps.",
    "da": "Informal, direct Danish — the norm for consumer apps.",
    "de": "Use the informal \"du\" — standard for German consumer/finance apps aimed at younger users (N26, Trade Republic). Warm and direct; avoid stiff officialese and English calques. German typically runs longer than English — keep compounds tight so labels don't overflow.",
    "el": "Modern Greek; avoid overly formal or bureaucratic phrasing.",
    "en-AU": "Australian English spelling and idiom (e.g. \"organise\", \"colour\"). Relaxed, friendly tone.",
    "en-CA": "Canadian English spelling (mostly British: \"colour\", \"centre\").",
    "en-GB": "British English spelling and idiom (e.g. \"organise\", \"colour\", \"centre\").",
    "es": "Castilian Spanish; informal \"tú\" (standard for youth-oriented consumer apps), not a \"vosotros\"-formal register. Spain vocabulary (e.g. \"móvil\"). Modern, relaxed.",
    "es-MX": "Latin American Spanish; informal \"tú\". Neutral LatAm vocabulary (e.g. \"celular\"); avoid Spain-specific terms.",
    "fi": "Direct, natural Finnish app tone, not literal. Finnish runs long — keep UI labels tight.",
    "fr": "Use the informal \"tu\" — younger French fintech/lifestyle apps (Lydia, Revolut FR) address under-35s with \"tu\". Elegant and concise; prefer natural French terms over anglicisms. French app copy prizes clarté and a refined, slightly understated register over an enthusiastic one.",
    "fr-CA": "Canadian French; informal \"tu\" (standard in Québécois consumer-app copy). Prefer Québécois usage and OQLF-style avoidance of anglicisms where they differ from France French.",
    "he": "Modern Hebrew. Right-to-left: keep punctuation and any Latin tokens (e.g. \"iCloud\") correctly placed for RTL. Friendly register.",
    "hi": "Conversational Hindi in Devanagari. Keep the polite \"आप\" — Hindi app copy uses \"आप\" across audiences; \"तू\" would read as rude, not young. The modern feel comes from warmth, brevity, and natural English loanwords (e.g. \"budget\"), not informal pronouns.",
    "hr": "Modern Croatian; natural phrasing, not calqued.",
    "hu": "Modern Hungarian; avoid stiff or bureaucratic register. Hungarian runs long — keep labels tight.",
    "id": "Friendly, casual Indonesian as used in popular consumer apps.",
    "it": "Informal \"tu\" (standard for youth-oriented consumer apps). Natural Italian; avoid unnecessary anglicisms.",
    "ja": "Keep polite-friendly です/ます — Japanese app copy stays polite regardless of audience age; plain/casual form reads as off, not young. Get warmth through light, soft, approachable phrasing (Apple Japan's voice), not by dropping politeness; avoid stiff keigo. Use katakana for loanwords (e.g. アプリ). The English em-dash habit does not translate — restructure instead.",
    "ko": "Use the polite-friendly 해요체 — Korean app copy stays polite across ages; plain 반말 reads as wrong, not young. Warmth comes from clean, light phrasing and natural English loanwords (common in Korean tech), not from dropping politeness. Match Apple Korea's voice.",
    "ms": "Friendly, natural Malay as used in consumer apps.",
    "nb": "Informal, direct Norwegian (Bokmål) — the norm for consumer apps.",
    "nl": "Use the informal \"je\" — standard for Dutch consumer apps, especially for younger audiences (\"u\" reads as formal/older). Modern, relaxed register.",
    "pl": "Modern Polish for young adults — use the informal \"Ty\" (direct address) rather than formal \"Pan/Pani\". Friendly, natural, not stiff.",
    "pt-BR": "Brazilian Portuguese; informal, warm \"você\" (the natural informal address in Brazil). Brazilian orthography and vocabulary.",
    "pt-PT": "European Portuguese; informal \"tu\" (standard in youth-oriented PT app copy; \"você\" reads as distant). European orthography and vocabulary; avoid Brazilian-specific terms.",
    "ro": "Modern Romanian; natural phrasing.",
    "ru": "Use the informal \"ты\" — modern Russian app copy for young adults (Yandex, T-Bank lifestyle) uses \"ты\" to feel current and friendly. Natural, non-calque Russian.",
    "sk": "Modern Slovak; natural phrasing.",
    "sv": "Informal, direct Swedish — the norm for consumer apps.",
    "th": "Polite, friendly Thai — keep the polite particles (ครับ/ค่ะ) Thai app copy uses across audiences; the modern feel comes from light, contemporary phrasing, not from dropping politeness. Follow normal Thai spacing conventions.",
    "tr": "Modern Turkish for young adults; use the informal \"sen\" (standard in youth-oriented app copy; \"siz\" reads as formal/older). Friendly and natural.",
    "uk": "Modern Ukrainian; natural phrasing, not calqued from Russian or English.",
    "vi": "Friendly, natural Vietnamese as used in popular consumer apps.",
    "zh-Hans": "Simplified Chinese, mainland China conventions. Concise, modern app tone; avoid Taiwan-specific vocabulary. Mainland copy is punchy and benefit-dense — short rhythms land well, but keep it calm and avoid exclamation-heavy hype.",
    "zh-Hant": "Traditional Chinese, Taiwan conventions. Concise, modern app tone; avoid mainland-specific vocabulary.",
}

# Fallback for any locale without a specific note above: still steer register.
_GENERIC_NOTE = (
    "Write as a native speaker would for a modern consumer app: natural, idiomatic, "
    "never calqued. Register: use the informal address if modern youth-oriented app copy "
    "in this language uses it, but keep the polite/formal form if this language stays "
    "formal in app copy regardless of audience age — get the modern feel from fresh, light "
    "phrasing, not forced slang."
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
            entry["enChars"] = len(entry.get("value", ""))
            slice_source[k] = entry
        if not slice_source:
            continue
        locale_name = LOCALE_NAMES.get(locale, locale)
        regional_note = REGIONAL_NOTES.get(locale, _GENERIC_NOTE)
        glossary_block = build_glossary_block(
            [e.get("value", "") for e in slice_source.values()], locale, locale_name
        )
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
