#!/usr/bin/env python3
"""
Maintenance tool: regenerate scripts/translate_audit/plural_rules.py from CLDR.

This is the ONLY piece that needs a third-party dependency (`babel`, which bundles the
CLDR plural rules). It runs rarely — only to refresh the static map when the locale set
or the bundled CLDR version changes. The committed map (`plural_rules.py`) and the check
that reads it (`plural_completeness.py`) have **no** runtime dependency.

For each locale in locales.py it computes two sets of CLDR cardinal plural categories:
  - "required": the categories reachable by realistic **integer** counts (0..999), plus
    `other` (always the mandatory fallback). This is what a plural string must cover —
    it excludes large-number-only categories (e.g. Romance `many`, used only for compact
    millions, which an expense count never reaches).
  - "valid": every category the language's rule defines (for spurious-category detection).

Usage (requires babel):
  python3 -m pip install babel
  python3 scripts/translate_audit/_gen_plural_rules.py > scripts/translate_audit/plural_rules.py
"""

from __future__ import annotations

import sys
from pathlib import Path

CATALOG_DIR = Path(__file__).resolve().parents[1] / "translate_catalog"
sys.path.insert(0, str(CATALOG_DIR))
from locales import LOCALES  # noqa: E402

import babel  # noqa: E402
from babel import Locale  # noqa: E402

INTEGER_SAMPLE = range(0, 1000)


def parse_locale(code: str) -> Locale:
    """Parse a runtime locale code (e.g. 'zh-Hans', 'pt-PT', 'es-MX'), falling back to the
    base language if the region/script variant isn't a distinct CLDR locale."""
    try:
        return Locale.parse(code.replace("-", "_"))
    except Exception:
        return Locale.parse(code.split("-")[0])


def categories_for(code: str) -> tuple[list[str], list[str]]:
    rule = parse_locale(code).plural_form  # babel PluralRule
    valid = set(rule.tags) | {"other"}
    required = {rule(n) for n in INTEGER_SAMPLE} | {"other"}
    order = ["zero", "one", "two", "few", "many", "other"]
    return ([c for c in order if c in required], [c for c in order if c in valid])


def main() -> int:
    rows = {code: categories_for(code) for code in LOCALES}
    out = sys.stdout
    out.write('"""Per-locale CLDR cardinal plural categories — GENERATED, do not hand-edit.\n\n')
    out.write(f"Source: babel {babel.__version__} (bundled CLDR). Regenerate with\n")
    out.write("scripts/translate_audit/_gen_plural_rules.py. See that file for the definitions of\n")
    out.write('`required` (integer-reachable, 0..999, + other) vs `valid` (full rule tag set).\n"""\n\n')
    out.write("# locale -> {\"required\": [...integer-reachable...], \"valid\": [...full set...]}\n")
    out.write("PLURAL_RULES: dict[str, dict[str, list[str]]] = {\n")
    for code in LOCALES:
        required, valid = rows[code]
        out.write(f'    "{code}": {{"required": {required}, "valid": {valid}}},\n')
    out.write("}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
