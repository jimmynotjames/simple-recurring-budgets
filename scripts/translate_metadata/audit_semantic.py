#!/usr/bin/env python3
"""
Semantic audit of the committed App Store listing under fastlane/metadata/<storefront>/: voice,
transcreation, keyword/ASO quality, cultural fit, brand and false claims, graded by one
`metadata-audit-locale` agent per storefront. `audit.py` is the structural (limits) check.

Flow:
  1. --dispatch [storefront ...]   write tmp/metadata-audit-prompts/{S}.md (English source, the
                                   storefront's current fields, its CULTURAL_NOTES entry, limits)
  2. fan out the auditors          each writes tmp/metadata-audit-outputs/{S}.json
  3. --report [storefront ...]     triage report; --json, --min-severity
  4. --write-manifest [--min-severity S] [storefront ...]
                                   turn findings into tmp/metadata-inputs/{manifest,source}.json,
                                   so dispatch_prompts.py re-transcreates the flagged fields
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
# --write-manifest target: the same files extract.py writes, so the existing
# dispatch_prompts.py → metadata-locale → validate → merge path can remediate.
INPUTS_DIR = REPO_ROOT / "tmp" / "metadata-inputs"
MANIFEST_PATH = INPUTS_DIR / "manifest.json"
SOURCE_OUT_PATH = INPUTS_DIR / "source.json"

sys.path.insert(0, str(SCRIPT_DIR))
# Import the *metadata* dispatch_prompts first, while SCRIPT_DIR is path[0] — the module name
# `dispatch_prompts` also exists in translate_catalog/, and metadata_locales' own path setup can
# otherwise shadow it.
from dispatch_prompts import CULTURAL_NOTES, _GENERIC_NOTE  # noqa: E402
import app_config  # noqa: E402
from metadata_locales import (  # noqa: E402
    FIELD_BYTE_LIMITS,
    FIELD_LIMITS,
    SOURCE_LOCALE,
    STOREFRONT_LOCALES,
    STOREFRONT_NAMES,
    STOREFRONT_TO_RUNTIME,
    TRANSLATABLE_FIELDS,
    glossary_lines,
    store_name,
)
from prompt_render import compact_json, render  # noqa: E402

SEVERITY_RANK = {"high": 3, "medium": 2, "low": 1}
RTL_LANGUAGES = {"ar", "he", "ur"}


def read_field(locale: str, field: str) -> str:
    path = METADATA_DIR / locale / f"{field}.txt"
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def has_translation(storefront: str) -> bool:
    return any(read_field(storefront, f) for f in TRANSLATABLE_FIELDS)


def audit_field(value: str, field: str, *, measure: bool) -> dict:
    """A field as the auditor sees it: its value, its limit, and (with `measure`) its current
    length, in bytes for byte-limited `keywords` and in characters otherwise."""
    if field in FIELD_BYTE_LIMITS:
        entry = {"value": value, "byteLimit": FIELD_BYTE_LIMITS[field]}
        if measure:
            entry["bytes"] = len(value.encode("utf-8"))
    else:
        entry = {"value": value, "charLimit": FIELD_LIMITS.get(field)}
        if measure:
            entry["chars"] = len(value)
    return entry


def render_audit_prompt(template: str, storefront: str, source: dict, current: dict) -> str:
    rtl = STOREFRONT_TO_RUNTIME.get(storefront, storefront).split("-")[0] in RTL_LANGUAGES
    sections = {"rtl"} if rtl else set()
    glossary = glossary_lines(storefront)
    if glossary:
        sections.add("glossary")
    return render(
        template,
        {
            "LOCALE_NAME": STOREFRONT_NAMES.get(storefront, storefront),
            "LOCALE_CODE": storefront,
            "REGIONAL_NOTE": CULTURAL_NOTES.get(storefront, _GENERIC_NOTE),
            "SOURCE_JSON": compact_json(source),
            "CURRENT_JSON": compact_json(current),
            "STORE_NAME": store_name(METADATA_DIR, storefront),
            "GLOSSARY": glossary,
            "AUDIT_FIELDS": " | ".join(TRANSLATABLE_FIELDS),
        },
        sections,
        known={"rtl", "glossary"},
    )


# ----------------------------------------------------------------- dispatch

def cmd_dispatch(storefronts: list[str]) -> int:
    if not TEMPLATE_PATH.exists():
        print(f"ERROR: missing {TEMPLATE_PATH}", file=sys.stderr)
        return 1
    template = app_config.load_template(TEMPLATE_PATH)
    source = {f: audit_field(read_field(SOURCE_LOCALE, f), f, measure=False)
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
        current = {f: audit_field(read_field(sf, f), f, measure=True)
                   for f in TRANSLATABLE_FIELDS if read_field(sf, f)}
        prompt = render_audit_prompt(template, sf, source, current)
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


# --------------------------------------------------------------- remediate

def _english_source() -> dict[str, dict]:
    """en-US authored translatable fields, in extract.py's source.json shape."""
    return {f: {"value": read_field(SOURCE_LOCALE, f), "charLimit": FIELD_LIMITS.get(f)}
            for f in TRANSLATABLE_FIELDS if read_field(SOURCE_LOCALE, f)}


def cmd_write_manifest(storefronts: list[str], min_severity: str) -> int:
    """Turn audit findings at/above `min_severity` into a re-transcreation manifest.

    Writes tmp/metadata-inputs/{manifest,source}.json in the exact shape
    `extract.py --missing` produces, scoped to the flagged (storefront, field)
    pairs — so the standard `dispatch_prompts.py` → metadata-locale → validate →
    merge path can fix exactly what the auditors flagged, with no ad-hoc plumbing.
    The per-field issues/suggestions stay in tmp/metadata-audit-outputs/{sf}.json
    for the remediation dispatch to feed each translator.
    """
    targets = storefronts or [s for s in STOREFRONT_LOCALES if s != SOURCE_LOCALE]
    threshold = SEVERITY_RANK[min_severity]
    source = _english_source()
    manifest: dict[str, list[str]] = {}
    missing: list[str] = []

    for sf in targets:
        path = OUTPUTS_DIR / f"{sf}.json"
        if not path.exists():
            missing.append(sf)
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"  ⚠ {sf}.json invalid JSON — skipping", file=sys.stderr)
            continue
        fields: set[str] = set()
        for f in data.get("findings", []) if isinstance(data, dict) else []:
            if not isinstance(f, dict):
                continue
            field = f.get("field")
            sev = f.get("severity", "medium")
            if sev not in SEVERITY_RANK:
                sev = "medium"
            # Only fields we can actually re-transcreate (authored in en-US source).
            if field in source and SEVERITY_RANK[sev] >= threshold:
                fields.add(field)
        if fields:
            manifest[sf] = sorted(fields)

    INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    (REPO_ROOT / "tmp" / "metadata-outputs").mkdir(parents=True, exist_ok=True)
    with SOURCE_OUT_PATH.open("w", encoding="utf-8") as fh:
        json.dump(source, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")
    with MANIFEST_PATH.open("w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")

    pairs = sum(len(v) for v in manifest.values())
    print(f"Remediation manifest: {len(manifest)} storefront(s), {pairs} field(s) "
          f"at/above '{min_severity}' → {MANIFEST_PATH}")
    if missing:
        print(f"  ({len(missing)} storefront(s) had no audit output — run --dispatch "
              "and the auditors first.)")
    if not manifest:
        print("  Nothing to remediate at this severity — the listing passed the "
              "semantic audit. ✓")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = parser.add_mutually_exclusive_group(required=True)
    g.add_argument("--dispatch", action="store_true", help="Compose per-storefront semantic audit prompts.")
    g.add_argument("--report", action="store_true", help="Aggregate auditor findings into a report.")
    g.add_argument("--write-manifest", action="store_true",
                   help="Write a re-transcreation manifest for findings at/above --min-severity "
                        "(extract.py shape) so dispatch_prompts.py can remediate them.")
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
    if args.write_manifest:
        return cmd_write_manifest(args.storefronts, args.min_severity)
    return cmd_report(args.storefronts, args.min_severity, args.json)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
