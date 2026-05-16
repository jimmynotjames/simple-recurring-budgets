#!/usr/bin/env python3
"""
Scan production Swift source files for two categories of problems.

ERRORS (exit 1) — hard-coded natural-language strings:
  Text("English text with spaces") where the argument looks like prose rather
  than a dotted localization key. These strings bypass xcstrings keying and
  will never be translated. Fix by using Text(String(localized: "key",
  comment: "...")) or, for locale-invariant strings, Text(verbatim: "...").

  Suppression (rare, documented exceptions only):
    Add  // check-strings:ignore  on the same line.

WARNINGS (no exit code change) — likely debug print() calls:
  Any non-commented print() in production Swift files. Intentional console
  output (e.g. a ConsoleAnalyticsClient) can be suppressed with the same
  // check-strings:ignore comment.

Scans: simple-recurring-budgets/**/*.swift (production target only).
Skips: *Tests.swift, *UITests.swift, test target directories.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "simple-recurring-budgets"

SUPPRESS_MARKER = "check-strings:ignore"

# Matches Text("...") where the string arg contains at least one space —
# the clearest signal that it's prose rather than a "dotted.key" identifier.
# Does NOT match Text(verbatim: "...") because verbatim: precedes the quote.
# Does NOT match Text(someVariable) or Text(String(localized: "key", ...)).
_NATURAL_LANG_TEXT_RE = re.compile(
    r'\bText\s*\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"'
)

# Matches a print( call that isn't part of a Swift comment on the same line.
_PRINT_RE = re.compile(r'\bprint\s*\(')
_COMMENT_LINE_RE = re.compile(r"^\s*//")


def _looks_like_natural_language(s: str) -> bool:
    """Return True if the string looks like prose rather than a localization key."""
    return " " in s


def _collect_swift_files() -> list[Path]:
    return [
        p for p in SOURCE_DIR.rglob("*.swift")
        if not (p.name.endswith("Tests.swift") or p.name.endswith("UITests.swift"))
    ]


def check(files: list[Path]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    for path in sorted(files):
        rel = path.relative_to(REPO_ROOT)
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            errors.append(f"{rel}: could not read file: {exc}")
            continue

        for lineno, raw_line in enumerate(lines, start=1):
            line = raw_line.rstrip()
            location = f"{rel}:{lineno}"

            # Skip pure comment lines for both checks.
            if _COMMENT_LINE_RE.match(line):
                continue

            suppressed = SUPPRESS_MARKER in line

            # --- Error: natural-language string literal in Text() ---
            for m in _NATURAL_LANG_TEXT_RE.finditer(line):
                s = m.group(1)
                if _looks_like_natural_language(s) and not suppressed:
                    errors.append(
                        f"  HARDCODED  {location}\n"
                        f"             Text({s!r}) — use Text(String(localized:\"key\","
                        f" comment:\"...\")) or Text(verbatim:\"...\") for non-translated strings"
                    )

            # --- Warning: print() call ---
            if _PRINT_RE.search(line) and not suppressed:
                snippet = line.strip()[:80]
                warnings.append(f"  PRINT      {location}  {snippet}")

    return errors, warnings


def main() -> int:
    files = _collect_swift_files()
    if not files:
        print(f"check_source_strings: no Swift files found under {SOURCE_DIR}", file=sys.stderr)
        return 1

    errors, warnings = check(files)

    if warnings:
        print(f"check_source_strings: {len(warnings)} print() warning(s) — review before shipping:\n")
        for w in warnings:
            print(w)
        print()

    if errors:
        print(f"check_source_strings: {len(errors)} hard-coded string error(s):\n")
        for e in errors:
            print(e)
        print(
            "\nFix: replace Text(\"English text\") with Text(String(localized: \"dotted.key\","
            " comment: \"context\")) and run scripts/translate_catalog/ afterward.\n"
            "If a string is intentionally not translated, use Text(verbatim: \"...\") instead.\n"
            f"To suppress a known exception, add  // {SUPPRESS_MARKER}  on the same line."
        )
        return 1

    summary = f"check_source_strings: {len(files)} file(s) clean."
    if warnings:
        summary += f" ({len(warnings)} print() warning(s) above)"
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
