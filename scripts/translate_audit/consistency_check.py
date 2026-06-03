#!/usr/bin/env python3
"""
Deterministic cross-key terminology consistency check for Localizable.xcstrings.

Many English strings are reused across multiple keys ("Cancel" under 8 keys,
"Add Funds" under 2, ...). Nothing in the translate pipeline guarantees that two
keys with identical English get the *same* translation, so they drift. This script
finds that drift — no LLM, no cost — and (optionally) emits a re-translation manifest
for the divergent set so the glossary-aware translate flow can converge them.

It is the deterministic complement to the LLM `consistency` finding the auditor
(scripts/translate_audit/) raises; run both.

How it works:
  - Group translatable keys by their *normalized* English value (casefold + collapsed
    whitespace) so "Add Funds" and "Add funds" land in one group.
  - For each group with >= --min-keys keys, for each locale, collect the distinct
    current translations across those keys. More than one distinct value = a divergence.
  - Classify: `word-choice` (the translations differ even after casefold — a real
    inconsistency) vs `casing-only` (they match after casefold — often legitimate when
    the English itself is cased differently by context, e.g. a title vs a sentence).

Reuses scripts/translate_catalog/{locales.py, extract.py} via import (no duplication).

Usage:
  python3 scripts/translate_audit/consistency_check.py [options] [locale ...]

  --min-keys N        only groups of at least N keys sharing English (default 2)
  --ignore-casing     suppress casing-only divergences (report word-choice only)
  --json              machine-readable output
  --write-manifest    write tmp/translate-inputs/{manifest,source}.json for every key in a
                      divergent group (per locale), in the shape extract.py --missing produces,
                      so the translate-new-strings flow (now glossary-aware) re-converges them
  locale ...          restrict to these locales (default: all in locales.py)

Exit code: 0 if no divergences (at/above the active filter), else 1.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"
CATALOG_DIR = REPO_ROOT / "scripts" / "translate_catalog"
TRANSLATE_INPUTS_DIR = REPO_ROOT / "tmp" / "translate-inputs"

sys.path.insert(0, str(CATALOG_DIR))
from locales import LOCALES  # noqa: E402
from extract import extract_format_specifiers  # noqa: E402


def normalize(value: str) -> str:
    """Casefold + collapse internal whitespace, for grouping equivalent English strings."""
    return " ".join(value.split()).casefold()


def stringunit_value(localization: dict | None) -> str | None:
    """Flat stringUnit value, or None if absent or a plural/device variations block."""
    if not localization or "variations" in localization:
        return None
    value = localization.get("stringUnit", {}).get("value")
    return value if value else None


def is_translatable(entry: dict) -> bool:
    return entry.get("shouldTranslate", True)


def build_groups(strings: dict) -> dict[str, list[str]]:
    """normalized English -> [keys] for translatable keys with a flat English value."""
    groups: dict[str, list[str]] = defaultdict(list)
    for key, entry in strings.items():
        if not is_translatable(entry):
            continue
        en = stringunit_value(entry.get("localizations", {}).get("en"))
        if not en:
            continue
        groups[normalize(en)].append(key)
    return groups


def english_label(strings: dict, keys: list[str]) -> str:
    """A representative English label for a group; note casing variants if any."""
    variants = sorted({stringunit_value(strings[k].get("localizations", {}).get("en")) or "" for k in keys})
    if len(variants) == 1:
        return variants[0]
    return " / ".join(variants)  # the English itself is cased differently across keys


def find_divergences(strings: dict, locales: list[str], min_keys: int, ignore_casing: bool) -> list[dict]:
    groups = build_groups(strings)
    findings: list[dict] = []
    for _norm, keys in groups.items():
        if len(keys) < min_keys:
            continue
        eng = english_label(strings, keys)
        for locale in locales:
            # key -> translation in this locale (only keys actually translated here)
            by_key: dict[str, str] = {}
            for k in keys:
                val = stringunit_value(strings[k].get("localizations", {}).get(locale))
                if val is not None:
                    by_key[k] = val
            distinct = set(by_key.values())
            if len(distinct) <= 1:
                continue
            casing_only = len({v.casefold() for v in distinct}) == 1
            if casing_only and ignore_casing:
                continue
            findings.append({
                "english": eng,
                "locale": locale,
                "kind": "casing-only" if casing_only else "word-choice",
                "keys": sorted(keys),
                "variants": sorted({f"{v}" for v in distinct}),
                "by_key": by_key,
            })
    findings.sort(key=lambda f: (f["kind"], f["english"].casefold(), f["locale"]))
    return findings


def _glossary_canonical_by_norm() -> dict[str, dict[str, str]]:
    """normalized English term -> {locale: canonical translation}, from glossary.json (if any).
    Lets the manifest skip keys already sitting on the canonical instead of re-translating them."""
    try:
        from dispatch_prompts import load_glossary  # reuse the catalog loader (cross-folder import)
    except Exception:
        return {}
    out: dict[str, dict[str, str]] = {}
    for term_en, entry in load_glossary().get("terms", {}).items():
        out[normalize(term_en)] = entry.get("translations", {})
    return out


def write_manifest(findings: list[dict], strings: dict) -> None:
    """Emit the divergent keys (per locale) so the translate flow re-converges them. When the
    group's English is a whole-string glossary term, keys already equal to that locale's canonical
    are skipped — only the off-canonical keys need re-translating."""
    canon = _glossary_canonical_by_norm()
    by_locale: dict[str, set[str]] = defaultdict(set)
    for f in findings:
        norm_en = normalize(stringunit_value(strings[f["keys"][0]].get("localizations", {}).get("en")) or "")
        canonical = canon.get(norm_en, {}).get(f["locale"])
        for k in f["keys"]:
            if k not in f["by_key"]:
                continue  # not translated in this locale → nothing to re-do
            if canonical is not None and f["by_key"][k] == canonical:
                continue  # already on the canonical glossary term → leave it
            by_locale[f["locale"]].add(k)
    manifest = {loc: sorted(keys) for loc, keys in sorted(by_locale.items()) if keys}
    union_keys = sorted({k for keys in by_locale.values() for k in keys})
    source_out = {}
    for k in union_keys:
        en = stringunit_value(strings[k].get("localizations", {}).get("en")) or ""
        source_out[k] = {
            "value": en,
            "comment": strings[k].get("comment", ""),
            "formatSpecifiers": extract_format_specifiers(en),
        }
    TRANSLATE_INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with (TRANSLATE_INPUTS_DIR / "source.json").open("w", encoding="utf-8") as f:
        json.dump(source_out, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    with (TRANSLATE_INPUTS_DIR / "manifest.json").open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    pairs = sum(len(v) for v in manifest.values())
    print(
        f"\nWrote re-convergence manifest: {len(union_keys)} key(s), {pairs} (key,locale) pair(s) "
        f"across {len(manifest)} locale(s) → {TRANSLATE_INPUTS_DIR}/"
        "\n  Next: run the glossary-aware translate-new-strings flow from step 2 (dispatch_prompts.py …)."
    )


def _counts(findings: list[dict]) -> dict:
    out = {"total": len(findings), "by_kind": {}, "locales": len({f["locale"] for f in findings})}
    for f in findings:
        out["by_kind"][f["kind"]] = out["by_kind"].get(f["kind"], 0) + 1
    return out


def print_report(findings: list[dict], args) -> None:
    if not findings:
        print(f"\n✓ No cross-key divergences (min-keys={args.min_keys}"
              f"{', word-choice only' if args.ignore_casing else ''}). Consistent. ✓")
        return
    current_kind = None
    for f in findings:
        if f["kind"] != current_kind:
            current_kind = f["kind"]
            print(f"\n{'=' * 6} {current_kind.upper()} {'=' * 6}")
        print(f"\n■ \"{f['english']}\" [{f['locale']}]  ({len(f['keys'])} keys)")
        print(f"    variants:  {'  ⟂  '.join(f['variants'])}")
        for k in sorted(f["by_key"]):
            print(f"      {k}  →  {f['by_key'][k]}")
    c = _counts(findings)
    print(f"\n{'-' * 60}")
    print(f"Summary: {c['total']} divergence(s) across {c['locales']} locale(s) — by kind {c['by_kind']}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--min-keys", type=int, default=2, help="Only groups of >= N keys sharing English (default 2).")
    parser.add_argument("--ignore-casing", action="store_true", help="Suppress casing-only divergences.")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--write-manifest", action="store_true")
    parser.add_argument("locales", nargs="*", help="Locales to check (default: all in locales.py).")
    args = parser.parse_args(argv)

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 2
    locales = args.locales if args.locales else LOCALES
    unknown = [loc for loc in locales if loc not in LOCALES]
    if unknown:
        print(f"ERROR: not target locales: {unknown}", file=sys.stderr)
        return 2

    with CATALOG_PATH.open(encoding="utf-8") as f:
        catalog = json.load(f)
    strings: dict = catalog.get("strings", {})

    findings = find_divergences(strings, locales, args.min_keys, args.ignore_casing)

    if args.json:
        printable = [{k: v for k, v in f.items() if k != "by_key"} | {"by_key": f["by_key"]} for f in findings]
        print(json.dumps({"counts": _counts(findings), "findings": printable}, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_report(findings, args)

    if args.write_manifest:
        if findings:
            write_manifest(findings, strings)
        else:
            print("\nNothing divergent — manifest not written.")

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
