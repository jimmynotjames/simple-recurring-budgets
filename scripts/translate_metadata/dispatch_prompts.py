#!/usr/bin/env python3
"""
Compose ready-to-dispatch transcreation prompts, one file per target storefront,
by combining PROMPT_TEMPLATE.md with the manifest written by `extract.py --missing`.

For each storefront S in tmp/metadata-inputs/manifest.json, writes
  tmp/metadata-prompts/{S}.md
containing the template with {LOCALE_NAME}, {LOCALE_CODE}, {CULTURAL_NOTE},
{BRAND}, and {SOURCE_JSON} substituted. The SOURCE_JSON slice contains only the
fields that storefront actually needs, each annotated with its character limit
and field-level guidance.

Usage:
  python3 scripts/translate_metadata/dispatch_prompts.py [--no-clean]

By default, also deletes any pre-existing tmp/metadata-outputs/{storefront}.json
files for the storefronts in the manifest, so subagents start clean and
validate.py --subset doesn't trip on leftover fields from a prior run. Pass
--no-clean to preserve those files.

The parent agent then reads each {storefront}.md and dispatches one
metadata-locale subagent per storefront with that prompt as input. Subagents
write their output JSON to tmp/metadata-outputs/{storefront}.json.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
INPUTS_DIR = REPO_ROOT / "tmp" / "metadata-inputs"
PROMPTS_DIR = REPO_ROOT / "tmp" / "metadata-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "metadata-outputs"
SOURCE_PATH = INPUTS_DIR / "source.json"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"
TEMPLATE_PATH = Path(__file__).parent / "PROMPT_TEMPLATE.md"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import (  # noqa: E402
    BRAND,
    FIELD_GUIDANCE,
    STOREFRONT_NAMES,
)

# Per-storefront cultural register notes (ASO/marketing copy). Inlined into the
# prompt where they materially help the model pick the right formality, script, or
# market vocabulary. Storefronts without an entry get a generic instruction. The
# sibling map for in-app UI copy is REGIONAL_NOTES in
# scripts/translate_catalog/dispatch_prompts.py (keyed by runtime locale code, not
# the App Store Connect storefront code used here — see metadata_locales.py).
#
# DELIBERATELY NOT DRY (see issue #173, closed without code consolidation). This map
# and REGIONAL_NOTES overlap only in the *formality decision* per language; the rest
# is genuinely different (ASO positioning, keyword-unbundling, marketer voice here vs
# UI dialect/length there), and some markets phrase the formality call differently for
# marketing. Single-sourcing the prose required a per-storefront override map that
# re-duplicated the formality sentence anyway, so it was abandoned. Future agents: do
# NOT re-file this as a DRY violation — honor the SYNC RULE instead.
#
# SYNC RULE: if you change the *formality decision* for a market here (e.g. flip de-DE
# from "du" to "Sie"), make the matching change in REGIONAL_NOTES for that language's
# runtime locale, and vice versa. Wording may differ; the formality call must not.
CULTURAL_NOTES: dict[str, str] = {
    "ar-SA": "Write in Modern Standard Arabic (MSA), not a regional dialect. Register: MSA marketing addresses all audiences with the same standard forms — there is no casual/formal pronoun split to toggle, so achieve the young, modern feel through fresh, light, contemporary phrasing rather than colloquialism. Right-to-left: keep punctuation and any Latin brand tokens correctly placed for RTL. Warm but clean register. Positioning: budgeting and saving carry positive, prudent-stewardship connotations here — frame Wren as helping you manage money wisely and with dignity, never as fixing overspending. Avoid imagery that implies the user is bad with money.",
    "bn-BD": "Conversational Bengali (Bangla) in Bengali script, marketing to young adults. Keep the polite \"আপনি\" — Bengali app copy stays polite across audiences; the casual \"তুমি\"/\"তুই\" reads as overfamiliar, not young. Get the modern feel from warmth, brevity, and the natural English loanwords (\"budget\", \"track\") Bengali speakers expect. Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Bengali-script terms with the common English loanwords people actually type.",
    "ca": "Natural, friendly Catalan as used in Apple's Catalan UI.",
    "cs": "Friendly, modern Czech app tone; natural phrasing over literal calques.",
    "da": "Informal, direct Danish — the norm for consumer apps.",
    "de-DE": "Use the informal \"du\" — standard for German consumer finance/lifestyle apps aimed at younger users (N26, Trade Republic). Warm and direct; avoid stiff officialese and English calques. Positioning: German users value precision, privacy, and substance over hype — lean into the calm/trustworthy/private traits and concrete benefits; understatement reads as credible here, marketing superlatives read as cheap. The privacy point (iCloud, no servers, no bank logins) lands especially well.",
    "el": "Friendly, modern Greek; avoid overly formal or bureaucratic phrasing.",
    "en-AU": "Australian English spelling and idiom (e.g. \"organise\", \"colour\"). Relaxed, friendly tone.",
    "en-CA": "Canadian English spelling (mostly British: \"colour\", \"centre\").",
    "en-GB": "British English spelling and idiom (e.g. \"organise\", \"colour\", \"centre\").",
    "es-ES": "Castilian Spanish; informal \"tú\" (standard for youth-oriented consumer apps). Spain vocabulary (e.g. \"móvil\"). Modern, relaxed young-adult register.",
    "es-MX": "Latin American Spanish; informal \"tú\". Neutral LatAm vocabulary (e.g. \"celular\"); avoid Spain-specific terms. Modern, friendly young-adult register.",
    "fi": "Friendly, direct Finnish app tone; natural, not literal.",
    "fr-FR": "Use the informal \"tu\" — younger French fintech/lifestyle apps (Lydia, Revolut FR, Sumeria) market to under-35s with \"tu\". Still elegant and concise; prefer natural French terms over anglicisms where one exists. Positioning: French app copy prizes elegance and clarté — a refined, slightly understated register beats an enthusiastic American one. Let the calm/tidy traits carry; avoid breathless tone and avoid franglais.",
    "fr-CA": "Canadian French; informal \"tu\" (standard in Québécois consumer-app copy aimed at young adults). Prefer Québécois usage and OQLF-style avoidance of anglicisms where they differ from France French.",
    "gu-IN": "Conversational Gujarati in Gujarati script, marketing to young adults. Keep the polite \"તમે\" — Gujarati app copy stays polite across audiences; the casual \"તું\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Gujarati-script terms with the common English loanwords people actually type.",
    "he": "Modern Hebrew. Right-to-left: keep punctuation and any Latin brand tokens correctly placed for RTL. Friendly register.",
    "hi": "Conversational Hindi in Devanagari. Register: keep the polite \"आप\" — Hindi app copy uses \"आप\" across audiences regardless of age; the informal \"तू\" would read as wrong/rude, not young. Achieve the young, modern feel through warmth, brevity, and English loanwords (e.g. \"budget\", \"track\") that Hindi speakers naturally expect, not through informal pronouns.",
    "hr": "Friendly, modern Croatian; natural phrasing.",
    "hu": "Friendly, modern Hungarian; avoid stiff or bureaucratic register.",
    "id": "Friendly, casual Indonesian as used in popular consumer apps.",
    "it": "Informal \"tu\" (standard for youth-oriented consumer apps). Natural Italian; avoid unnecessary anglicisms. Modern, relaxed young-adult register.",
    "ja": "Register: keep polite-friendly です/ます — Japanese app copy stays polite regardless of audience age; plain/casual form would read as off, not young. Get the young, modern feel through light, soft, approachable phrasing (Apple Japan's voice), not through dropping politeness. Avoid stiff keigo. Use katakana for loanwords (e.g. アプリ). Positioning: Japanese app copy rewards quiet politeness, tidiness, and 'kawaii-adjacent' gentle warmth over bold claims — the calm/tidy/quietly-warm traits are a perfect fit; let them lead and keep superlatives out. Short, soft sentences; the em-dash habit of English does not translate, restructure instead. Keyword note: Japanese is not space-delimited, so the template's \"unbundle multi-word phrases into single comma-separated words\" rule does NOT apply mechanically — never split a term into individual characters or insert spaces. List each keyword as the complete, natural unit users actually type (kanji/katakana as appropriate, comma-separated), and prioritize correct standalone search terms over trying to engineer cross-field word recombinations.",
    "kn-IN": "Natural Kannada in Kannada script, marketing to young adults. Keep the polite \"ನೀವು\" — Kannada app copy stays polite across audiences; the casual \"ನೀನು\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Kannada-script terms with the common English loanwords people actually type.",
    "ko": "Register: use the polite-friendly 해요체 — Korean app copy stays polite across ages; the plain 반말 form would read as wrong, not young. The young, modern feel comes from clean, light phrasing and natural English loanwords (common in Korean tech/finance), not from dropping politeness. Match Apple Korea's app voice. Positioning: clean, modern, lightly warm; lean into light/quick/effortless; avoid heavy or preachy framing about saving money. Keyword note: Korean does use spaces between words, but do not over-split terms into syllables or particles to chase the template's recombination rule — list each keyword as the complete unit users actually type (comma-separated), favoring the natural search terms (including common English loanwords) over engineered fragments.",
    "ml-IN": "Natural Malayalam in Malayalam script, marketing to young adults. Keep the polite \"നിങ്ങൾ\" — Malayalam app copy addresses all audiences politely; the casual \"നീ\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Malayalam-script terms with the common English loanwords people actually type.",
    "mr-IN": "Conversational Marathi in Devanagari, marketing to young adults. Keep the polite \"तुम्ही\" — Marathi app copy stays polite across audiences; \"तू\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Devanagari terms with the common English loanwords people actually type.",
    "ms": "Friendly, natural Malay as used in consumer apps.",
    "nl-NL": "Use the informal \"je\" — standard for Dutch consumer apps, especially for younger audiences (\"u\" reads as formal/older). Modern, relaxed register.",
    "no": "Informal, direct Norwegian (Bokmål) — the norm for consumer apps.",
    "or-IN": "Natural Odia in Odia script, marketing to young adults. Keep the polite \"ଆପଣ\" — Odia app copy stays polite across audiences; the casual \"ତୁମେ\"/\"ତୁ\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Odia-script terms with the common English loanwords people actually type.",
    "pa-IN": "Conversational Punjabi in Gurmukhi (Indian Punjabi) script, marketing to young adults. Keep the polite \"ਤੁਸੀਂ\" — Punjabi app copy stays polite across audiences; \"ਤੂੰ\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Gurmukhi terms with the common English loanwords people actually type.",
    "pl": "Modern Polish for young adults. Polish app marketing to under-35s commonly uses the informal \"Ty\" (direct address) rather than the formal \"Pan/Pani\" — use \"Ty\". Friendly, natural, not stiff.",
    "pt-BR": "Brazilian Portuguese; informal, warm \"você\" (the natural informal address in Brazil). Brazilian orthography and vocabulary. Modern, friendly young-adult register.",
    "pt-PT": "European Portuguese; informal \"tu\" (standard in youth-oriented PT app copy; \"você\" can read as distant). European orthography and vocabulary; avoid Brazilian-specific terms.",
    "ro": "Friendly, modern Romanian; natural phrasing.",
    "ru": "Use the informal \"ты\" — modern Russian app marketing to young adults (Yandex, Tinkoff/T-Bank lifestyle copy) uses \"ты\" to feel current and friendly. Natural, non-calque Russian; relaxed young-adult register.",
    "sk": "Friendly, modern Slovak; natural phrasing.",
    "sl-SI": "Modern Slovenian for young adults — use the informal \"ti\" (the formal \"vi\" reads as distant/official in youth-oriented consumer-app copy). Natural, non-calqued phrasing; avoid stiff or bureaucratic register. Let the calm/tidy traits carry rather than marketing hype.",
    "sv": "Informal, direct Swedish — the norm for consumer apps.",
    "ta-IN": "Natural Tamil in Tamil script, marketing to young adults. Keep the polite \"நீங்கள்\" — Tamil app copy stays polite across audiences; the casual \"நீ\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Tamil-script terms with the common English loanwords people actually type.",
    "te-IN": "Natural Telugu in Telugu script, marketing to young adults. Keep the polite \"మీరు\" — Telugu app copy stays polite across audiences; the casual \"నువ్వు\" reads as overfamiliar. Get the modern feel from warmth, brevity, and natural English loanwords (\"budget\", \"track\"). Positioning: budgeting and saving carry positive, prudent-household connotations — frame Wren as managing money calmly and wisely, never as fixing bad habits. Keyword/ASO: many users search in English or Roman-script transliteration, so mix natural Telugu-script terms with the common English loanwords people actually type.",
    "th": "Polite, friendly Thai — keep the polite particles (ครับ/ค่ะ) that Thai app copy uses across audiences; the young, modern feel comes from light, friendly, contemporary phrasing, not from dropping politeness. Follow normal Thai spacing conventions; keep it light and approachable.",
    "tr": "Modern Turkish for young adults; use the informal \"sen\" (standard in youth-oriented lifestyle/fintech app copy; \"siz\" reads as formal/older). Friendly and natural.",
    "uk": "Friendly, modern Ukrainian; natural phrasing, not calqued from Russian or English.",
    "ur-PK": "Conversational Urdu in Nastaliq (Arabic) script, marketing to young adults. Keep the polite \"آپ\" — Urdu app copy uses \"آپ\" across audiences; \"تم\"/\"تو\" reads as overfamiliar or rude, not young. Right-to-left: keep punctuation and any Latin brand/tech tokens (\"Wren\", \"iCloud\") correctly placed for RTL. Positioning: budgeting and saving carry positive, prudent-stewardship connotations — frame Wren as managing money wisely and with dignity, never as fixing overspending. Get the modern feel from warm, light phrasing and natural English loanwords (\"budget\", \"track\"), not informal pronouns. Keyword/ASO: many users search in English or Roman-Urdu transliteration, so mix natural Urdu-script terms with the common English loanwords people actually type.",
    "vi": "Friendly, natural Vietnamese as used in popular consumer apps.",
    "zh-Hans": "Simplified Chinese, mainland China conventions. Concise, modern app tone; avoid Taiwan-specific vocabulary. Positioning: mainland app copy is punchy and benefit-dense — short four-character rhythms and concrete value land well, but keep it calm and avoid the exclamation-heavy hype common in local ads. Note: iCloud-based privacy framing is less of a selling point here; emphasize speed, simplicity, and everyday usefulness instead. Avoid implying any bank-account linking. Keyword note: Chinese is not space-delimited, so the template's \"unbundle multi-word phrases into single comma-separated words\" rule does NOT apply mechanically — never split a term into individual characters or insert spaces. List each keyword as the complete, natural unit users actually type (comma-separated), and prioritize correct standalone search terms over trying to engineer cross-field word recombinations.",
    "zh-Hant": "Traditional Chinese, Taiwan conventions. Avoid mainland-specific vocabulary. Keyword note: Chinese is not space-delimited, so the template's \"unbundle multi-word phrases into single comma-separated words\" rule does NOT apply mechanically — never split a term into individual characters or insert spaces. List each keyword as the complete, natural unit users actually type (comma-separated), and prioritize correct standalone search terms over trying to engineer cross-field word recombinations.",
}

_GENERIC_NOTE = (
    "Write as a native marketer for this market would: natural, idiomatic, and "
    "benefit-driven. Avoid literal, calqued translations. Register: target young "
    "adults (late-20s) — use the informal address if modern youth-oriented app "
    "marketing in this language uses it, but keep the polite/formal form if this "
    "language stays formal in app copy regardless of audience age. Get the young, "
    "modern feel from fresh, light phrasing, not from forced slang."
)


def build_prompt_source(slice_fields: list[str], source: dict) -> dict:
    """Annotate each needed field with its English value, limit, and guidance."""
    out: dict[str, dict] = {}
    for field in slice_fields:
        if field not in source:
            continue
        out[field] = {
            "english": source[field]["value"],
            "charLimit": source[field]["charLimit"],
            "guidance": FIELD_GUIDANCE.get(field, ""),
        }
    return out


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
    template = TEMPLATE_PATH.read_text(encoding="utf-8")

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
        locale_name = STOREFRONT_NAMES.get(storefront, storefront)
        cultural_note = CULTURAL_NOTES.get(storefront, _GENERIC_NOTE)
        prompt = (
            template.replace("{LOCALE_NAME}", locale_name)
            .replace("{LOCALE_CODE}", storefront)
            .replace("{CULTURAL_NOTE}", cultural_note)
            .replace("{BRAND}", BRAND)
            .replace("{SOURCE_JSON}", json.dumps(prompt_source, ensure_ascii=False, indent=2, sort_keys=True))
        )
        out_path = PROMPTS_DIR / f"{storefront}.md"
        out_path.write_text(prompt, encoding="utf-8")
        print(f"  Wrote {len(prompt_source)} field(s) for {storefront} → {out_path}")

    print(f"\n{len(manifest)} prompt file(s) written to {PROMPTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
