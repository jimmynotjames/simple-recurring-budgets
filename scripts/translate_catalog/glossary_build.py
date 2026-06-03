#!/usr/bin/env python3
"""
Build (and extend) the app translation glossary: scripts/translate_catalog/glossary.json.

The glossary gives each recurring app term ONE canonical translation per locale, so two
keys with the same English ("Add Funds" under several keys) stay consistent, and so that
"Add Expense" can reuse the glossary's "Add" and "Expense". It is consulted by
dispatch_prompts.py (translation) and audit_dispatch.py (audit), and grown by glossary_sync.py.

This script is an orchestration *primitive* — it never calls an LLM itself. It prepares
inputs/prompts and merges agent outputs, exactly like extract.py/dispatch_prompts.py/merge.py.
The parent agent runs the `glossary-locale` (Opus) agents between --dispatch and --merge.

Pipeline:
  1. --candidates          deterministic: mine duplicate strings + frequent terms
                           → tmp/glossary/candidates.json
  2. --write-curation-prompt   compose tmp/glossary/curation_prompt.md (English-only) for ONE
                           Opus curation agent to pick the focused term set → tmp/glossary/terms.json
  3. --dispatch [loc ...]  from terms.json, write tmp/glossary/prompts/{locale}.md for the
                           glossary-locale agents (term + context + examples + regional note)
  4. --merge               assemble terms.json + tmp/glossary/outputs/{locale}.json into
                           glossary.json (merging into any existing terms); force protected
                           nouns to themselves; validate locale coverage

Reuses scripts/translate_catalog/{locales.py, dispatch_prompts.py} (LOCALES, LOCALE_NAMES,
REGIONAL_NOTES, _GENERIC_NOTE) — no duplication.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"
GLOSSARY_PATH = SCRIPT_DIR / "glossary.json"
GLOSSARY_DIR = REPO_ROOT / "tmp" / "glossary"
CANDIDATES_PATH = GLOSSARY_DIR / "candidates.json"
TERMS_PATH = GLOSSARY_DIR / "terms.json"
PROMPTS_DIR = GLOSSARY_DIR / "prompts"
OUTPUTS_DIR = GLOSSARY_DIR / "outputs"
CURATION_PROMPT_OUT = GLOSSARY_DIR / "curation_prompt.md"
CURATION_TEMPLATE = SCRIPT_DIR / "GLOSSARY_CURATION_PROMPT.md"
TRANSLATE_TEMPLATE = SCRIPT_DIR / "GLOSSARY_TRANSLATE_PROMPT.md"

sys.path.insert(0, str(SCRIPT_DIR))
from locales import LOCALES, LOCALE_NAMES  # noqa: E402
from dispatch_prompts import REGIONAL_NOTES, _GENERIC_NOTE  # noqa: E402

PROTECTED = ["Wren", "iCloud", "Carry-Over"]

# Small English stopword set — enough to keep the frequent-word candidate pool to content words.
STOPWORDS = {
    "the", "a", "an", "to", "of", "in", "on", "for", "and", "or", "is", "are", "was", "be",
    "this", "that", "these", "those", "it", "its", "your", "you", "we", "us", "our", "with",
    "at", "by", "as", "from", "into", "out", "up", "down", "no", "not", "yet", "but", "so",
    "if", "when", "then", "than", "can", "cannot", "will", "would", "has", "have", "had",
    "do", "does", "did", "been", "being", "they", "them", "their", "what", "which", "%@",
}
TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")


def load_catalog() -> dict:
    with CATALOG_PATH.open(encoding="utf-8") as f:
        return json.load(f).get("strings", {})


def en_value(entry: dict) -> str | None:
    loc = entry.get("localizations", {}).get("en")
    if not loc or "variations" in loc:
        return None
    v = loc.get("stringUnit", {}).get("value")
    return v if v else None


def translatable_items(strings: dict) -> list[tuple[str, str, str]]:
    """(key, english, comment) for translatable keys with a flat English value."""
    out = []
    for key, entry in strings.items():
        if not entry.get("shouldTranslate", True):
            continue
        v = en_value(entry)
        if v:
            out.append((key, v, entry.get("comment", "")))
    return out


def load_glossary() -> dict:
    if GLOSSARY_PATH.exists():
        with GLOSSARY_PATH.open(encoding="utf-8") as f:
            return json.load(f)
    return {"meta": {"model": "opus", "version": 1}, "protected": PROTECTED, "terms": {}}


# ---------------------------------------------------------------- candidates

def cmd_candidates() -> int:
    strings = load_catalog()
    items = translatable_items(strings)

    dup: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for key, en, comment in items:
        dup[en].append((key, comment))
    duplicate_strings = [
        {"en": en, "count": len(ks), "keys": [k for k, _ in ks], "comments": sorted({c for _, c in ks if c})}
        for en, ks in dup.items() if len(ks) >= 2
    ]
    duplicate_strings.sort(key=lambda d: (-d["count"], d["en"].casefold()))

    word_df: dict[str, set[str]] = defaultdict(set)
    for key, en, _ in items:
        for tok in {t.casefold() for t in TOKEN_RE.findall(en)}:
            if tok in STOPWORDS or len(tok) < 2:
                continue
            word_df[tok].add(key)
    frequent_words = [
        {"word": w, "df": len(keys), "exampleKeys": sorted(keys)[:6]}
        for w, keys in word_df.items() if len(keys) >= 3
    ]
    frequent_words.sort(key=lambda d: (-d["df"], d["word"]))

    GLOSSARY_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "duplicateStrings": duplicate_strings,
        "frequentWords": frequent_words,
        "protected": PROTECTED,
        "totalKeys": len(items),
    }
    with CANDIDATES_PATH.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Candidates → {CANDIDATES_PATH}: {len(duplicate_strings)} duplicate string(s), "
          f"{len(frequent_words)} frequent word(s) (df>=3), from {len(items)} keys.")
    return 0


# ---------------------------------------------------------------- curation prompt

def _string_inventory(strings: dict) -> list[dict]:
    return [{"key": k, "en": en, "comment": c} for k, en, c in sorted(translatable_items(strings))]


def cmd_write_curation_prompt() -> int:
    if not CANDIDATES_PATH.exists():
        print(f"ERROR: {CANDIDATES_PATH} not found. Run --candidates first.", file=sys.stderr)
        return 1
    if not CURATION_TEMPLATE.exists():
        print(f"ERROR: missing {CURATION_TEMPLATE}", file=sys.stderr)
        return 1
    candidates = json.loads(CANDIDATES_PATH.read_text(encoding="utf-8"))
    inventory = _string_inventory(load_catalog())
    prompt = (
        CURATION_TEMPLATE.read_text(encoding="utf-8")
        .replace("{CANDIDATES_JSON}", json.dumps(candidates, ensure_ascii=False, indent=2))
        .replace("{STRING_INVENTORY_JSON}", json.dumps(inventory, ensure_ascii=False, indent=2))
        .replace("{TERMS_OUT_PATH}", str(TERMS_PATH))
    )
    GLOSSARY_DIR.mkdir(parents=True, exist_ok=True)
    CURATION_PROMPT_OUT.write_text(prompt, encoding="utf-8")
    print(f"Curation prompt → {CURATION_PROMPT_OUT}\n"
          f"  Dispatch ONE glossary-locale (Opus) agent to read it and write {TERMS_PATH}.")
    return 0


# ---------------------------------------------------------------- dispatch

def _load_terms() -> list[dict]:
    if not TERMS_PATH.exists():
        raise SystemExit(f"ERROR: {TERMS_PATH} not found. Run the curation step (or glossary_sync --detect) first.")
    data = json.loads(TERMS_PATH.read_text(encoding="utf-8"))
    terms = data.get("terms", data) if isinstance(data, dict) else data
    if not isinstance(terms, list):
        raise SystemExit(f"ERROR: {TERMS_PATH} must contain a 'terms' list.")
    return terms


def _term_examples(term_en: str, strings: dict, limit: int = 4) -> list[str]:
    """Example source strings that contain the term (for translation context)."""
    needle = term_en.casefold()
    out = []
    for _k, en, _c in translatable_items(strings):
        if needle in en.casefold():
            out.append(en)
        if len(out) >= limit:
            break
    return out


def cmd_dispatch(locales: list[str]) -> int:
    if not TRANSLATE_TEMPLATE.exists():
        print(f"ERROR: missing {TRANSLATE_TEMPLATE}", file=sys.stderr)
        return 1
    terms = _load_terms()
    strings = load_catalog()
    template = TRANSLATE_TEMPLATE.read_text(encoding="utf-8")
    requested = locales if locales else LOCALES
    unknown = [loc for loc in requested if loc not in LOCALES]
    if unknown:
        print(f"ERROR: not target locales: {unknown}", file=sys.stderr)
        return 2

    # Build the per-term payload once (examples are locale-independent).
    term_payload = []
    for t in terms:
        en = t["en"]
        term_payload.append({
            "en": en,
            "context": t.get("context", ""),
            "partOfSpeech": t.get("partOfSpeech", ""),
            "examples": t.get("examples") or _term_examples(en, strings),
        })

    PROMPTS_DIR.mkdir(parents=True, exist_ok=True)
    for old in PROMPTS_DIR.glob("*.md"):
        old.unlink()
    for locale in sorted(requested):
        # Protected nouns need no translation; the agent is told to keep them as-is, but we
        # also force them at merge time. Still include them so the agent sees the full set.
        prompt = (
            template.replace("{LOCALE_NAME}", LOCALE_NAMES.get(locale, locale))
            .replace("{LOCALE_CODE}", locale)
            .replace("{REGIONAL_NOTE}", REGIONAL_NOTES.get(locale, _GENERIC_NOTE))
            .replace("{PROTECTED_JSON}", json.dumps(PROTECTED, ensure_ascii=False))
            .replace("{TERMS_JSON}", json.dumps(term_payload, ensure_ascii=False, indent=2))
        )
        (PROMPTS_DIR / f"{locale}.md").write_text(prompt, encoding="utf-8")
    # Clear stale outputs for the locales we're dispatching.
    if OUTPUTS_DIR.exists():
        for locale in requested:
            stale = OUTPUTS_DIR / f"{locale}.json"
            if stale.exists():
                stale.unlink()
    print(f"Wrote {len(requested)} glossary prompt(s) for {len(terms)} term(s) → {PROMPTS_DIR}\n"
          f"  Dispatch one glossary-locale (Opus) agent per file; each writes {OUTPUTS_DIR}/{{locale}}.json "
          "as {{\"<English term>\": \"<translation>\"}}.")
    return 0


# ---------------------------------------------------------------- merge

def cmd_merge() -> int:
    terms = _load_terms()
    glossary = load_glossary()
    existing = glossary.setdefault("terms", {})

    missing_outputs = []
    locale_outputs: dict[str, dict] = {}
    for locale in LOCALES:
        path = OUTPUTS_DIR / f"{locale}.json"
        if not path.exists():
            missing_outputs.append(locale)
            continue
        try:
            locale_outputs[locale] = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"  ⚠ {locale}.json is not valid JSON — skipping (re-dispatch it)")
    if missing_outputs:
        print(f"  ⚠ No output for {len(missing_outputs)} locale(s): {', '.join(missing_outputs)}")

    added, updated = 0, 0
    incomplete: list[str] = []
    for t in terms:
        en = t["en"]
        is_protected = en in PROTECTED
        translations: dict[str, str] = {}
        for locale in LOCALES:
            if is_protected:
                translations[locale] = en  # force protected nouns to themselves
            else:
                val = locale_outputs.get(locale, {}).get(en)
                if val:
                    translations[locale] = val
        present = sum(1 for loc in LOCALES if loc in translations)
        if present < len(LOCALES):
            incomplete.append(f"{en} ({present}/{len(LOCALES)})")
        entry = {
            "en": en,
            "context": t.get("context", ""),
            "partOfSpeech": t.get("partOfSpeech", ""),
            "sourceKeys": t.get("sourceKeys", []),
            "translations": translations,
        }
        if en in existing:
            # Merge: keep any prior translations not re-produced this round.
            merged = dict(existing[en].get("translations", {}))
            merged.update(translations)
            entry["translations"] = merged
            updated += 1
        else:
            added += 1
        existing[en] = entry

    glossary["protected"] = PROTECTED
    glossary.setdefault("meta", {})["builtAt"] = _dt.datetime.now(_dt.timezone.utc).isoformat()
    glossary["meta"]["model"] = "opus"
    with GLOSSARY_PATH.open("w", encoding="utf-8") as f:
        json.dump(glossary, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Merged glossary → {GLOSSARY_PATH}: +{added} new, {updated} updated; {len(existing)} terms total.")
    if incomplete:
        print(f"  ⚠ {len(incomplete)} term(s) missing some locales (re-dispatch those locales): {incomplete[:8]}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = parser.add_mutually_exclusive_group(required=True)
    g.add_argument("--candidates", action="store_true", help="Mine duplicate strings + frequent terms.")
    g.add_argument("--write-curation-prompt", action="store_true", help="Compose the Opus curation prompt.")
    g.add_argument("--dispatch", action="store_true", help="Write per-locale glossary translation prompts.")
    g.add_argument("--merge", action="store_true", help="Merge agent outputs into glossary.json.")
    parser.add_argument("locales", nargs="*", help="Locales for --dispatch (default: all).")
    args = parser.parse_args(argv)

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 2
    if args.candidates:
        return cmd_candidates()
    if args.write_curation_prompt:
        return cmd_write_curation_prompt()
    if args.dispatch:
        return cmd_dispatch(args.locales)
    if args.merge:
        return cmd_merge()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
