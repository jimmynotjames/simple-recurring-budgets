#!/usr/bin/env python3
"""
Deterministic "untranslated copy" detector for Localizable.xcstrings.

Flags a non-English locale whose value is byte-identical to the English source yet
carries `state: translated`, which every state check (check_translations.py) passes.
"Value == English" alone is too noisy (cognates, loanwords, en-* variants), so a
holdout is reported only as an *outlier*: most other non-English locales translated
the key away from English, and at most --max-holdouts locales kept it. Terms the
glossary keeps in English are auto-allowed; the rest of the known-good residue is
in ALLOWLIST.

Usage:
  python3 scripts/translate_audit/untranslated_copies.py [options] [locale ...]

  --max-holdouts N        max locales sharing the English value to still flag (default 2)
  --min-translated-share F  min fraction of other non-English locales that DID translate
                            the key, for it to count as "broadly translated" (default 0.85)
  --json                  machine-readable output
  locale ...              restrict REPORTING to these locales (the share is always computed
                          over all non-English targets); default: all in locales.py

Exit code: 0 if no suspected untranslated copies, else 1.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIR = REPO_ROOT / "scripts" / "translate_catalog"
sys.path.insert(0, str(CATALOG_DIR))
from paths import CATALOG_PATH  # noqa: E402
import app_config  # noqa: E402
GLOSSARY_PATH = app_config.GLOSSARY_PATH

from locales import LOCALES  # noqa: E402

# The glossary (i18n/glossary.json) is the authority on which whole-string
# terms are *deliberately* kept in English per locale — protected terms (i18n/app.json `protected`)
# and genuine cognates the language uses verbatim (de "Name"). load_glossary_kept_english()
# turns it into {locale: {kept-English terms}}
# so those are auto-allowed without hand-maintenance; re-run the glossary pipeline to change them.
#
# ALLOWLIST only carries the residue the glossary can't speak to: identical-to-English values that
# aren't whole glossary terms (a phrase, a cognate on a key with no glossary term). Each is a
# deliberate human call — add it to i18n/untranslated_allowlist.json, with the reason, when
# triage confirms a flag is fine.
ALLOWLIST: set[tuple[str, str]] = app_config.untranslated_allowlist()


def load_glossary_kept_english() -> dict[str, set[str]]:
    """{locale: set of English term-values the glossary keeps in English for that locale}.

    A term is "kept-English" for a locale when its canonical translation equals the term itself;
    protected terms count for every locale. Used to auto-allow legitimate verbatim-English values.
    """
    try:
        glossary = json.loads(GLOSSARY_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    protected = set(glossary.get("protected", []))
    terms: dict = glossary.get("terms", {})
    kept: dict[str, set[str]] = {}
    for locale in LOCALES:
        s = set(protected)
        for term, entry in terms.items():
            if entry.get("translations", {}).get(locale) == term:
                s.add(term)
        kept[locale] = s
    return kept

# Matches %@, %1$@, %lld, %.2f, %% so format-only strings don't count as "translatable".
_FMT = re.compile(r"%%|%(?:\d+\$)?[0-9.*]*[@a-zA-Z]")


def english_family(locale: str) -> bool:
    """en and its regional variants legitimately share the English text."""
    return locale == "en" or locale.startswith("en-")


def translatable(value: str) -> bool:
    """True if, after removing format specifiers, any letter remains to translate."""
    return bool(re.search(r"[^\W\d_]", _FMT.sub("", value), re.UNICODE))


def stringunit_value(localization: dict | None) -> str | None:
    """Flat stringUnit value, or None if absent or a plural/device variations block."""
    if not localization or "variations" in localization:
        return None
    value = localization.get("stringUnit", {}).get("value")
    return value or None


def find_untranslated_copies(strings: dict, report_locales: list[str], max_holdouts: int,
                             min_share: float) -> list[dict]:
    targets = [loc for loc in LOCALES if not english_family(loc)]
    report_set = set(report_locales)
    kept_english = load_glossary_kept_english()
    findings: list[dict] = []

    for key, entry in strings.items():
        if not entry.get("shouldTranslate", True):
            continue
        localizations = entry.get("localizations", {})
        en = stringunit_value(localizations.get("en"))
        if not en or not translatable(en):
            continue

        present = {loc: v for loc in targets if (v := stringunit_value(localizations.get(loc))) is not None}
        holdouts = [loc for loc, v in present.items() if v == en]
        if not holdouts:
            continue
        translated_count = len(present) - len(holdouts)
        share = translated_count / len(present) if present else 0.0

        # Outlier test: broadly translated elsewhere, only a few holdouts.
        if len(holdouts) > max_holdouts or share < min_share:
            continue

        for loc in holdouts:
            if (key, loc) in ALLOWLIST or loc not in report_set:
                continue
            if en in kept_english.get(loc, ()):  # glossary deliberately keeps this term in English here
                continue
            findings.append({
                "key": key,
                "locale": loc,
                "value": en,
                "translated_elsewhere": translated_count,
                "holdouts": sorted(holdouts),
            })

    findings.sort(key=lambda f: (f["locale"], f["key"]))
    return findings


def print_report(findings: list[dict]) -> None:
    if not findings:
        print("\n✓ No suspected untranslated copies (English-identical outliers). ✓")
        return
    print(f"\n{len(findings)} suspected untranslated copy(ies) "
          "— value identical to English in a key translated everywhere else:\n")
    current = None
    for f in findings:
        if f["locale"] != current:
            current = f["locale"]
            print(f"  [{current}]")
        others = len(f["holdouts"]) - 1
        also = f" (also: {[h for h in f['holdouts'] if h != f['locale']]})" if others else ""
        print(f"    {f['key']}  =  {f['value']!r}   "
              f"[translated in {f['translated_elsewhere']} other locales{also}]")
    print("\nTriage each: translate it (force, since state is already `translated`), "
          "or add (key, locale) to i18n/untranslated_allowlist.json with the reason if the match is a real cognate.")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--max-holdouts", type=int, default=2)
    parser.add_argument("--min-translated-share", type=float, default=0.85)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("locales", nargs="*", help="Restrict reporting to these locales.")
    args = parser.parse_args(argv)

    if not CATALOG_PATH.exists():
        print(f"ERROR: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        return 2
    report_locales = args.locales if args.locales else [loc for loc in LOCALES if not english_family(loc)]
    unknown = [loc for loc in report_locales if loc not in LOCALES]
    if unknown:
        print(f"ERROR: not target locales: {unknown}", file=sys.stderr)
        return 2

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    strings: dict = catalog.get("strings", {})
    findings = find_untranslated_copies(strings, report_locales, args.max_holdouts, args.min_translated_share)

    if args.json:
        print(json.dumps({"count": len(findings), "findings": findings},
                         ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_report(findings)

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
