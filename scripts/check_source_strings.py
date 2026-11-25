#!/usr/bin/env python3
"""
Scan production Swift source files for two categories of problems.

ERRORS (exit 1) — unkeyed user-facing strings:
  A quoted literal passed straight to a text-bearing SwiftUI or UIKit API
  (Text("…"), Button("…"), .navigationTitle("…"), .accessibilityLabel("…"),
  label.text = "…", UIBarButtonItem(title: "…"), String(format: "…"), …) that
  is not a dotted localization key. These strings bypass the String Catalog and
  will never be translated. Fix by keying them:
      String(localized: "screen.purpose.detail", defaultValue: "…", comment: "…")
  or, for locale-invariant text, Text(verbatim: "…"). AGENTS.md §"Cross-cutting concerns".

  Suppression (rare, documented exceptions only):
    Add  // check-strings:ignore  on the same line.

WARNINGS (no exit code change) — likely debug print() calls:
  Any non-commented print() in production Swift files. Intentional console
  output (e.g. a ConsoleAnalyticsClient) can be suppressed with the same
  // check-strings:ignore comment.

Scans: the app target (paths.SOURCE_DIR) only.
Skips: *Tests.swift, *UITests.swift, and DesignExplorations/ (gitignored scratch).

Not caught: literals bound to a plain `String` property or a custom initializer
(`SomeRow(title: "…")`, `private let message = "…"`). Those are a review item
in the create-pr cross-cutting audit.

Usage:
  python3 scripts/check_source_strings.py [--json]

  --json   emit {"errors": [{file, line, message}], "warnings": [...]}
           instead of the human-readable report
"""

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

sys.path.insert(0, str(REPO_ROOT / "scripts" / "translate_catalog"))
from paths import SOURCE_DIR  # noqa: E402

SUPPRESS_MARKER = "check-strings:ignore"
SKIPPED_DIRS = {"DesignExplorations"}

_QUOTED = r'"([^"\\]*(?:\\.[^"\\]*)*)"'
# Same, but only when the literal opens with a capital letter: the ternary patterns below
# would otherwise fire on every `flag ? "a" : "b"` identifier switch in the tree.
_QUOTED_PROSE = r'"([A-Z][^"\\]*(?:\\.[^"\\]*)*)"'

# Each pattern's group 1 is the literal. `Text(verbatim: "…")` never matches because
# `verbatim:` precedes the quote; `Text(String(localized: …))` never matches because
# `String(` precedes it.
_LITERAL_PATTERNS = [
    re.compile(r"\b(?:Text|Button|Label|Toggle|TextField|SecureField|Section|Link|Menu)\s*\(\s*" + _QUOTED),
    re.compile(
        r"\.(?:navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|alert|"
        r"confirmationDialog|help|badge)\s*\(\s*" + _QUOTED
    ),
    re.compile(
        r"\.(?:text|title|placeholder|placeholderText|accessibilityLabel|accessibilityValue|"
        r"accessibilityHint|prompt)\s*=\s*" + _QUOTED
    ),
    re.compile(r"\bUIBarButtonItem\s*\(\s*title:\s*" + _QUOTED),
    re.compile(r"\bUIAlertAction\s*\(\s*title:\s*" + _QUOTED),
    re.compile(r"\bString\s*\(\s*format:\s*" + _QUOTED),
    # A ternary choosing between two capitalized literals is user-facing copy parked in a
    # local before it reaches a UI call, which the call-site patterns above cannot see.
    # Both branches are captured. The two continuation forms cover a ternary split across
    # lines, since this check is line-based; the leading `?`/`:` keeps a dictionary entry
    # (`"key": "Value"`) or a `case "x":` from matching.
    re.compile(r"\?\s+" + _QUOTED_PROSE + r"\s*:\s*" + _QUOTED_PROSE),
    re.compile(r"^\s*\?\s+" + _QUOTED_PROSE),
    re.compile(r"^\s*:\s+" + _QUOTED_PROSE),
]

# A dotted localization key: `screen.purpose.detail`. Anything else is prose.
_DOTTED_KEY_RE = re.compile(r"^[A-Za-z]\w*(?:\.\w+)+$")

# Matches a print( call that isn't part of a Swift comment on the same line.
_PRINT_RE = re.compile(r"\bprint\s*\(")
_COMMENT_LINE_RE = re.compile(r"^\s*//")


def _is_unkeyed(literal: str) -> bool:
    """Non-empty and not a dotted key ⇒ prose that bypasses the catalog."""
    return bool(literal.strip()) and not _DOTTED_KEY_RE.match(literal)


def _collect_swift_files() -> list[Path]:
    files = []
    for p in SOURCE_DIR.rglob("*.swift"):
        if p.name.endswith("Tests.swift") or p.name.endswith("UITests.swift"):
            continue
        if SKIPPED_DIRS & set(p.relative_to(SOURCE_DIR).parts[:-1]):
            continue
        files.append(p)
    return files


def check(files: list[Path]) -> tuple[list[dict], list[dict]]:
    errors: list[dict] = []
    warnings: list[dict] = []

    for path in sorted(files):
        rel = str(path.relative_to(REPO_ROOT))
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            errors.append({"file": rel, "line": 0, "message": f"could not read file: {exc}"})
            continue

        for lineno, raw_line in enumerate(lines, start=1):
            line = raw_line.rstrip()

            # Skip pure comment lines for both checks.
            if _COMMENT_LINE_RE.match(line):
                continue

            suppressed = SUPPRESS_MARKER in line

            # --- Error: unkeyed literal handed to a text-bearing API ---
            if not suppressed:
                seen: set[str] = set()
                for pattern in _LITERAL_PATTERNS:
                    for m in pattern.finditer(line):
                        # Every group is a literal; the ternary pattern captures two.
                        for s in m.groups():
                            if s is None or s in seen or not _is_unkeyed(s):
                                continue
                            seen.add(s)
                            errors.append({
                                "file": rel, "line": lineno,
                                "message": f"{s!r} — key it with String(localized:\"dotted.key\", defaultValue:, comment:) "
                                           "or use Text(verbatim:\"...\") for locale-invariant text",
                            })

            # --- Warning: print() call ---
            if _PRINT_RE.search(line) and not suppressed:
                snippet = line.strip()[:80]
                warnings.append({"file": rel, "line": lineno, "message": snippet})

    return errors, warnings


def _format_error(e: dict) -> str:
    return f"  UNKEYED    {e['file']}:{e['line']}\n             {e['message']}"


def _format_warning(w: dict) -> str:
    return f"  PRINT      {w['file']}:{w['line']}  {w['message']}"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", action="store_true",
                        help='Emit {"errors": [...], "warnings": [...]} instead of the human report.')
    args = parser.parse_args(argv)

    files = _collect_swift_files()
    if not files:
        if args.json:
            print(json.dumps({"errors": [{"message": f"no Swift files found under {SOURCE_DIR}"}], "warnings": []}))
        else:
            print(f"check_source_strings: no Swift files found under {SOURCE_DIR}", file=sys.stderr)
        return 1

    errors, warnings = check(files)

    if args.json:
        print(json.dumps({"errors": errors, "warnings": warnings}, ensure_ascii=False, indent=2))
        return 1 if errors else 0

    if warnings:
        print(f"check_source_strings: {len(warnings)} print() warning(s) — review before shipping:\n")
        for w in warnings:
            print(_format_warning(w))
        print()

    if errors:
        print(f"check_source_strings: {len(errors)} unkeyed string error(s):\n")
        for e in errors:
            print(_format_error(e))
        print(
            "\nFix: key the string — String(localized: \"dotted.key\", defaultValue: \"English\","
            " comment: \"context\") — and run the translate-new-strings skill afterward.\n"
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
    sys.exit(main(sys.argv[1:]))
