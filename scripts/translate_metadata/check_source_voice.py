#!/usr/bin/env python3
"""
Pre-flight voice check on the **English (en-US) App Store metadata source**.

The transcreation pipeline fans the en-US source out to 49 storefronts, so a
brand-voice slip in the source (an exclamation mark, ALL-CAPS shouting, a salesy
superlative) propagates everywhere and then gets independently re-flagged by all
49 semantic auditors — one source flaw becomes a whole audit+remediation cycle.
This catches it once, at the source, before any fan-out.

It enforces the **calm/understated** rule from PROMPT_TEMPLATE.md / the audit
rubric: "No exclamation marks, no ALL-CAPS shouting, no '!!!', no salesy
superlatives ('the best', 'amazing', 'revolutionary')."

These are **warnings, not hard errors** — there can be a legitimate reason to keep
one. The skill's source-ready confirmation runs this first and, on any finding,
halts and surfaces the warning to the human, who decides whether to fix the source
or proceed anyway. Exit code: 0 = clean, 1 = at least one possible voice issue.

Usage:
  python3 scripts/translate_metadata/check_source_voice.py [--json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
METADATA_DIR = REPO_ROOT / "fastlane" / "metadata"

sys.path.insert(0, str(SCRIPT_DIR))
from metadata_locales import SOURCE_LOCALE, TRANSLATABLE_FIELDS  # noqa: E402

# Salesy superlatives / hype words the voice rule calls out, plus close kin. Kept
# tight to avoid false positives on legitimate plain copy — this is a warn-and-ask
# gate, so a rare miss is fine; noisy false alarms are not.
SUPERLATIVES = [
    "the best", "best", "amazing", "revolutionary", "incredible", "ultimate",
    "awesome", "fantastic", "unbelievable", "world-class", "must-have",
    "number one", "guaranteed", "flawless", "magical", "stunning", "#1",
]
# Word-boundary alternation; longest first so "the best" wins over "best".
_SUPERLATIVE_RE = re.compile(
    r"(?<!\w)(" + "|".join(re.escape(w) for w in sorted(SUPERLATIVES, key=len, reverse=True)) + r")(?!\w)",
    re.IGNORECASE,
)
# A run of 4+ consecutive uppercase ASCII letters = shouting (e.g. AMAZING).
# 3-letter acronyms like USD stay under the bar.
_ALLCAPS_RE = re.compile(r"\b[A-Z]{4,}\b")


def read_field(field: str) -> str:
    path = METADATA_DIR / SOURCE_LOCALE / f"{field}.txt"
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def _snippet(text: str, start: int, end: int, pad: int = 24) -> str:
    lo = max(0, start - pad)
    hi = min(len(text), end + pad)
    out = text[lo:hi].replace("\n", " ⏎ ")
    return f"{'…' if lo else ''}{out}{'…' if hi < len(text) else ''}"


def scan_field(field: str, value: str) -> list[dict]:
    findings: list[dict] = []
    if "!" in value:
        i = value.index("!")
        findings.append({"field": field, "kind": "exclamation",
                         "match": "!", "snippet": _snippet(value, i, i + 1)})
    for m in _ALLCAPS_RE.finditer(value):
        findings.append({"field": field, "kind": "all-caps", "match": m.group(0),
                         "snippet": _snippet(value, m.start(), m.end())})
    for m in _SUPERLATIVE_RE.finditer(value):
        findings.append({"field": field, "kind": "superlative", "match": m.group(0),
                         "snippet": _snippet(value, m.start(), m.end())})
    return findings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", action="store_true", help="Machine-readable output.")
    args = parser.parse_args(argv)

    if not (METADATA_DIR / SOURCE_LOCALE).exists():
        print(f"ERROR: en-US source folder not found at {METADATA_DIR / SOURCE_LOCALE}", file=sys.stderr)
        return 2

    authored = [(f, read_field(f)) for f in TRANSLATABLE_FIELDS if read_field(f)]
    findings: list[dict] = []
    for field, value in authored:
        findings.extend(scan_field(field, value))

    if args.json:
        print(json.dumps({"findings": findings, "fields_checked": [f for f, _ in authored]},
                         ensure_ascii=False, indent=2, sort_keys=True))
        return 1 if findings else 0

    if not findings:
        print(f"check_source_voice: en-US source clean — no exclamation marks, "
              f"ALL-CAPS, or superlatives in {len(authored)} authored field(s).")
        return 0

    print(f"⚠ Source voice check — {len(findings)} possible voice issue(s) in the en-US source.")
    print("  Voice rule: calm/understated — no exclamation marks, no ALL-CAPS shouting, "
          "no salesy superlatives.")
    print("  These propagate to all 49 storefronts. Fix the en-US source, or confirm "
          "you want to keep them.\n")
    for f in findings:
        print(f"  ■ {f['field']:<16} {f['kind']:<11} {f['match']!r}")
        print(f"      …{f['snippet']}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
