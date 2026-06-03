#!/usr/bin/env python3
"""
Deterministic CLDR plural-completeness check for Localizable.xcstrings.

`validate.py` checks plural *shape* (valid category names, non-empty `other`, matching
format specifiers) but NOT completeness — a locale with only `one/other` passes even when
its language needs `one/few/many/other`. The semantic audit is supposed to catch this but is
unreliable (it missed Arabic shipping only `one/other`). This check closes that gap with no
LLM: for every plural key, it compares each locale's provided categories against the
CLDR-required set and flags gaps.

It's the deterministic complement to the LLM plural grading, mirroring how
`consistency_check.py` complements the LLM `consistency` finding.

Per locale (from the committed `plural_rules.py`, generated from CLDR via babel):
  - `required` — categories reachable by realistic integer counts (0..999) + `other`. A
    plural string MUST cover all of these. (Excludes large-number-only categories like the
    Romance `many`, which an expense count never reaches.)
  - `valid`    — every category the language's rule defines. A category outside this set is
    `spurious` (the language never uses it, e.g. `few` in German).

A locale's plural is flagged when it is **missing** a `required` category or includes a
**spurious** one. Categories that are `valid` but not `required` (e.g. Slovak `many`, only
for decimals) are accepted either way — no noise.

Usage:
  python3 scripts/translate_audit/plural_completeness.py [options] [locale ...]

  --json             machine-readable output
  --write-manifest   write tmp/translate-inputs/{manifest,source}.json for the incomplete
                     (key,locale) pairs (shape extract.py --missing produces, carrying the
                     `plural` source) so they re-translate via the standard flow
  locale ...         restrict to these locales (default: all in locales.py)

Exit code: 0 if every plural key is complete in every checked locale, else 1.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"
CATALOG_DIR = REPO_ROOT / "scripts" / "translate_catalog"
TRANSLATE_INPUTS_DIR = REPO_ROOT / "tmp" / "translate-inputs"

sys.path.insert(0, str(CATALOG_DIR))
from locales import LOCALES  # noqa: E402
from extract import localization_plural, extract_format_specifiers  # noqa: E402

sys.path.insert(0, str(Path(__file__).parent))
from plural_rules import PLURAL_RULES  # noqa: E402

_ORDER = ["zero", "one", "two", "few", "many", "other"]


def _ordered(cats) -> list[str]:
    s = set(cats)
    return [c for c in _ORDER if c in s]


def en_plural_keys(strings: dict) -> list[str]:
    """Keys whose English source is a plural-variations block (sorted)."""
    out = []
    for key, entry in strings.items():
        if not entry.get("shouldTranslate", True):
            continue
        if "plural" in entry.get("localizations", {}).get("en", {}).get("variations", {}):
            out.append(key)
    return sorted(out)


def find_incomplete(strings: dict, locales: list[str]) -> list[dict]:
    findings: list[dict] = []
    for key in en_plural_keys(strings):
        localizations = strings[key].get("localizations", {})
        for locale in locales:
            rule = PLURAL_RULES.get(locale)
            if not rule:
                continue  # unknown locale (shouldn't happen for LOCALES)
            present = localization_plural(localizations.get(locale))
            if present is None:
                continue  # locale has no plural block for this key — coverage is check_translations' job
            got = set(present.keys())
            required = set(rule["required"])
            valid = set(rule["valid"])
            missing = required - got
            spurious = got - valid
            if missing or spurious:
                findings.append({
                    "key": key,
                    "locale": locale,
                    "required": _ordered(required),
                    "got": _ordered(got),
                    "missing": _ordered(missing),
                    "spurious": _ordered(spurious),
                })
    findings.sort(key=lambda f: (f["key"], f["locale"]))
    return findings


def write_manifest(findings: list[dict], strings: dict) -> None:
    by_locale: dict[str, set[str]] = {}
    for f in findings:
        by_locale.setdefault(f["locale"], set()).add(f["key"])
    manifest = {loc: sorted(keys) for loc, keys in sorted(by_locale.items()) if keys}
    union_keys = sorted({k for keys in by_locale.values() for k in keys})
    source_out = {}
    for k in union_keys:
        en = strings[k].get("localizations", {}).get("en", {})
        plural = localization_plural(en)
        comment = strings[k].get("comment", "")
        ref = (plural or {}).get("other", "") if plural else ""
        source_out[k] = {
            "plural": plural,
            "comment": comment,
            "formatSpecifiers": extract_format_specifiers(ref),
        }
    TRANSLATE_INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with (TRANSLATE_INPUTS_DIR / "source.json").open("w", encoding="utf-8") as f:
        json.dump(source_out, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    with (TRANSLATE_INPUTS_DIR / "manifest.json").open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    pairs = sum(len(v) for v in manifest.values())
    print(f"\nWrote plural re-translation manifest: {len(union_keys)} key(s), {pairs} pair(s) "
          f"across {len(manifest)} locale(s) → {TRANSLATE_INPUTS_DIR}/"
          "\n  Next: run the translate-new-strings flow from step 2 (dispatch_prompts.py …).")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
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
        strings = json.load(f).get("strings", {})

    plural_keys = en_plural_keys(strings)
    findings = find_incomplete(strings, locales)

    if args.json:
        print(json.dumps({"pluralKeys": plural_keys, "findings": findings}, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        if not plural_keys:
            print("No plural keys in the catalog — nothing to check.")
        elif not findings:
            print(f"✓ All {len(plural_keys)} plural key(s) complete across {len(locales)} locale(s). ✓")
        else:
            for f in findings:
                bits = []
                if f["missing"]:
                    bits.append(f"missing {f['missing']}")
                if f["spurious"]:
                    bits.append(f"spurious {f['spurious']}")
                print(f"■ {f['locale']:<8} {f['key']}")
                print(f"    required: {f['required']}  got: {f['got']}  → {'; '.join(bits)}")
            print(f"\n{'-' * 60}\nSummary: {len(findings)} incomplete (key,locale) pair(s) "
                  f"over {len(plural_keys)} plural key(s).")

    if args.write_manifest and findings:
        write_manifest(findings, strings)
    elif args.write_manifest:
        print("\nNothing incomplete — manifest not written.")

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
