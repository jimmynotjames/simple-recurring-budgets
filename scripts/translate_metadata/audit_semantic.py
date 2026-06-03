#!/usr/bin/env python3
"""
SEMANTIC quality audit for the App Store metadata transcreations — the marketing-copy
counterpart to scripts/translate_audit/ (which audits in-app strings).

`audit.py` (sibling) checks only presence + char limits (structural). This script grades the
*quality* of the localized store listing: voice/tone, transcreation (native vs. calqued),
keyword/ASO effectiveness, cultural fit, brand, and false claims — via one Opus auditor per
storefront, exactly like the catalog audit.

It reads the **committed** localized metadata under fastlane/metadata/<storefront>/ (not the
tmp/ fan-out), so you can audit what's actually shipping.

Flow:
  1. --dispatch [storefronts]   compose tmp/metadata-audit-prompts/{storefront}.md (en source +
                                that storefront's current fields + the cultural note + limits)
  2. fan out one metadata-audit-locale (Opus) agent per prompt → tmp/metadata-audit-outputs/{sf}.json
  3. --report [storefronts]     aggregate findings into a triage report; --json; --min-severity

Reuses metadata_locales (limits/fields/names) and dispatch_prompts.CULTURAL_NOTES (no duplication).

Usage:
  python3 scripts/translate_metadata/audit_semantic.py --dispatch [storefront ...]
  python3 scripts/translate_metadata/audit_semantic.py --report [--min-severity medium] [--json] [storefront ...]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
METADATA_DIR = REPO_ROOT / "fastlane" / "metadata"
PROMPTS_DIR = REPO_ROOT / "tmp" / "metadata-audit-prompts"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "metadata-audit-outputs"
TEMPLATE_PATH = SCRIPT_DIR / "AUDIT_PROMPT_TEMPLATE.md"

sys.path.insert(0, str(SCRIPT_DIR))
# Import the *metadata* dispatch_prompts first, while SCRIPT_DIR is path[0] — the module name
# `dispatch_prompts` also exists in translate_catalog/, and metadata_locales' own path setup can
# otherwise shadow it.
from dispatch_prompts import CULTURAL_NOTES  # noqa: E402
from metadata_locales import (  # noqa: E402
    FIELD_LIMITS,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    STOREFRONT_NAMES,
    TRANSLATABLE_FIELDS,
)

SEVERITY_RANK = {"high": 3, "medium": 2, "low": 1}
_GENERIC_NOTE = "Write as a native ASO copywriter for this market would: natural, idiomatic, never calqued."


def read_field(locale: str, field: str) -> str:
    path = METADATA_DIR / locale / f"{field}.txt"
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def has_translation(storefront: str) -> bool:
    return any(read_field(storefront, f) for f in TRANSLATABLE_FIELDS)


# ----------------------------------------------------------------- dispatch

def cmd_dispatch(storefronts: list[str]) -> int:
    if not TEMPLATE_PATH.exists():
        print(f"ERROR: missing {TEMPLATE_PATH}", file=sys.stderr)
        return 1
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    source = {f: {"value": read_field(SOURCE_LOCALE, f), "charLimit": FIELD_LIMITS.get(f)}
              for f in TRANSLATABLE_FIELDS if read_field(SOURCE_LOCALE, f)}
    if not source:
        print(f"ERROR: no English source metadata in {METADATA_DIR / SOURCE_LOCALE}", file=sys.stderr)
        return 1

    targets = storefronts or [s for s in STOREFRONT_LOCALES if s != SOURCE_LOCALE]
    PROMPTS_DIR.mkdir(parents=True, exist_ok=True)
    for old in PROMPTS_DIR.glob("*.md"):
        old.unlink()

    written, skipped = 0, []
    for sf in targets:
        if not has_translation(sf):
            skipped.append(sf)
            continue
        current = {f: {"value": read_field(sf, f), "chars": len(read_field(sf, f)), "charLimit": FIELD_LIMITS.get(f)}
                   for f in TRANSLATABLE_FIELDS if read_field(sf, f)}
        prompt = (
            template.replace("{LOCALE_NAME}", STOREFRONT_NAMES.get(sf, sf))
            .replace("{LOCALE_CODE}", sf)
            .replace("{REGIONAL_NOTE}", CULTURAL_NOTES.get(sf, _GENERIC_NOTE))
            .replace("{SOURCE_JSON}", json.dumps(source, ensure_ascii=False, indent=2, sort_keys=True))
            .replace("{CURRENT_JSON}", json.dumps(current, ensure_ascii=False, indent=2, sort_keys=True))
        )
        (PROMPTS_DIR / f"{sf}.md").write_text(prompt, encoding="utf-8")
        if OUTPUTS_DIR.exists():
            stale = OUTPUTS_DIR / f"{sf}.json"
            if stale.exists():
                stale.unlink()
        written += 1

    print(f"Wrote {written} metadata-audit prompt(s) → {PROMPTS_DIR}")
    if skipped:
        print(f"Skipped {len(skipped)} storefront(s) with no localized metadata yet: {skipped[:8]}"
              f"{'…' if len(skipped) > 8 else ''}")
    if not written:
        print("Nothing to audit — no localized metadata found. (Localize metadata first, then re-run.)")
    return 0


# ----------------------------------------------------------------- report

def cmd_report(storefronts: list[str], min_severity: str, as_json: bool) -> int:
    targets = storefronts or [s for s in STOREFRONT_LOCALES if s != SOURCE_LOCALE]
    threshold = SEVERITY_RANK[min_severity]
    all_findings: list[dict] = []
    summaries: dict[str, str] = {}
    missing: list[str] = []

    for sf in targets:
        path = OUTPUTS_DIR / f"{sf}.json"
        if not path.exists():
            missing.append(sf)
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"  ⚠ {sf}.json invalid JSON — re-dispatch", file=sys.stderr)
            continue
        for f in data.get("findings", []) if isinstance(data, dict) else []:
            if not isinstance(f, dict) or "field" not in f:
                continue
            sev = f.get("severity", "medium")
            if sev not in SEVERITY_RANK:
                sev = "medium"
            all_findings.append({"storefront": sf, "severity": sev, **{k: f.get(k, "") for k in
                                 ("field", "category", "current", "issue", "suggestion")}})
        if isinstance(data, dict) and data.get("locale_summary"):
            summaries[sf] = data["locale_summary"]

    kept = [f for f in all_findings if SEVERITY_RANK[f["severity"]] >= threshold]
    kept.sort(key=lambda f: (-SEVERITY_RANK[f["severity"]], f["storefront"], f["field"]))

    if as_json:
        print(json.dumps({"findings": kept, "summaries": summaries, "missing": missing},
                         ensure_ascii=False, indent=2, sort_keys=True))
        return 1 if kept else 0

    if missing:
        print(f"⚠ No audit output yet for {len(missing)} storefront(s): {', '.join(missing[:10])}"
              f"{'…' if len(missing) > 10 else ''}")
    if not kept:
        print(f"\n✓ No metadata findings at/above '{min_severity}'.")
        return 0
    current_sev = None
    for f in kept:
        if f["severity"] != current_sev:
            current_sev = f["severity"]
            print(f"\n{'=' * 6} {current_sev.upper()} {'=' * 6}")
        print(f"\n■ {f['storefront']:<8} {f['field']}  ({f['category']})")
        print(f"    current:  {f['current']}")
        if f["issue"]:
            print(f"    issue:    {f['issue']}")
        if f["suggestion"]:
            print(f"    suggest:  {f['suggestion']}")
    by_cat: dict[str, int] = {}
    for f in kept:
        by_cat[f["category"]] = by_cat.get(f["category"], 0) + 1
    print(f"\n{'-' * 60}\nSummary: {len(kept)} finding(s) at/above '{min_severity}' — by category {by_cat}")
    if summaries:
        print("\nPer-storefront summaries:")
        for sf in sorted(summaries):
            print(f"  [{sf}] {summaries[sf]}")
    return 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = parser.add_mutually_exclusive_group(required=True)
    g.add_argument("--dispatch", action="store_true", help="Compose per-storefront semantic audit prompts.")
    g.add_argument("--report", action="store_true", help="Aggregate auditor findings into a report.")
    parser.add_argument("--min-severity", choices=["high", "medium", "low"], default="low")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("storefronts", nargs="*", help="Storefronts (default: all targets).")
    args = parser.parse_args(argv)

    unknown = [s for s in args.storefronts if s not in STOREFRONT_LOCALES]
    if unknown:
        print(f"ERROR: not target storefronts: {unknown}", file=sys.stderr)
        return 2
    if args.dispatch:
        return cmd_dispatch(args.storefronts)
    return cmd_report(args.storefronts, args.min_severity, args.json)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
