#!/usr/bin/env python3
"""
Aggregate the per-locale audit findings in tmp/translate-audit-outputs/ into a single
triage report, and (optionally) emit a re-translation manifest for the flagged subset.

Modeled on scripts/translate_metadata/audit.py — the inspection + escalation tool so a
human (and the skill) never need ad-hoc `jq`/`python3 -c` to answer "what did the audit
find, how bad is it, and what should I re-translate?"

Inputs:
  tmp/translate-audit-outputs/{locale}.json  — findings from each auditor subagent
  tmp/translate-audit-inputs/audit_source.json — English + current translations, used for
      the deterministic length pre-filter AND to rebuild source.json for --write-manifest

Two kinds of findings are combined:
  [llm]   — judged by the auditor subagent (any category)
  [ratio] — a deterministic length flag: current translation is more than --max-expansion
            times the English length. Added only when the auditor did NOT already raise a
            `length` finding for that (locale, key). A raw ratio can't tell justified
            expansion from bloat, so treat [ratio] findings as "look at these," not verdicts.

Usage:
  python3 scripts/translate_audit/audit_report.py [options] [locale ...]

  --min-severity {high,medium,low}  only report/count/manifest findings at or above this
                                    (default: low — i.e. everything)
  --max-expansion FLOAT             length-ratio threshold for [ratio] findings (default 1.4)
  --json                            machine-readable output
  --write-manifest                  write tmp/translate-inputs/{manifest,source}.json for the
                                    flagged subset, in the shape extract.py --missing produces,
                                    so the translate-new-strings flow re-translates exactly them
  locale ...                        restrict to these locales (default: all in locales.py)

Exit code: 0 if no findings at/above --min-severity, else 1 (so it can gate a loop).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIR = REPO_ROOT / "scripts" / "translate_catalog"
AUDIT_SOURCE_PATH = REPO_ROOT / "tmp" / "translate-audit-inputs" / "audit_source.json"
OUTPUTS_DIR = REPO_ROOT / "tmp" / "translate-audit-outputs"
TRANSLATE_INPUTS_DIR = REPO_ROOT / "tmp" / "translate-inputs"

sys.path.insert(0, str(CATALOG_DIR))
from locales import LOCALES  # noqa: E402

SEVERITY_RANK = {"high": 3, "medium": 2, "low": 1}


def loads_tolerant(raw: str) -> dict:
    """Parse a findings JSON object, tolerating ```json fences or surrounding prose that a
    subagent may emit despite the JSON-only contract — so one stray locale doesn't force a
    re-dispatch during an unattended run."""
    text = raw.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            return json.loads(text[start:end + 1])
        raise


def ratio_severity(ratio: float) -> str:
    if ratio >= 2.0:
        return "high"
    if ratio >= 1.6:
        return "medium"
    return "low"


def load_findings(locale: str) -> tuple[list[dict], str, str]:
    """Return (findings, summary, state). state in {ok, missing, empty, badjson}."""
    path = OUTPUTS_DIR / f"{locale}.json"
    if not path.exists():
        return [], "", "missing"
    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return [], "", "empty"
    try:
        data = loads_tolerant(raw)
    except json.JSONDecodeError:
        return [], "", "badjson"
    findings = []
    for f in data.get("findings", []) if isinstance(data, dict) else []:
        if not isinstance(f, dict) or "key" not in f:
            continue
        sev = f.get("severity", "medium")
        if sev not in SEVERITY_RANK:
            sev = "medium"
        findings.append({
            "locale": locale,
            "key": f["key"],
            "severity": sev,
            "category": f.get("category", "tone"),
            "current": f.get("current", ""),
            "back_translation": f.get("back_translation", ""),
            "issue": f.get("issue", ""),
            "suggestion": f.get("suggestion", ""),
            "source": "llm",
        })
    summary = data.get("locale_summary", "") if isinstance(data, dict) else ""
    return findings, summary, "ok"


def deterministic_length_findings(
    source: dict, locales: list[str], llm: list[dict], max_expansion: float, min_chars: int
) -> list[dict]:
    """Flag (locale, key) whose current translation is >max_expansion× the English length,
    unless the auditor already raised a `length` finding for that pair.

    Skips translations shorter than ``min_chars``: on very short strings the ratio is
    unstable (e.g. "Retry"→"Erneut versuchen" is 3.2× but a fine 16-char button) and short
    strings rarely truncate, so flagging them is mostly noise. Truncation risk concentrates
    in genuinely long strings that also expanded a lot."""
    already = {(f["locale"], f["key"]) for f in llm if f.get("category") == "length"}
    out: list[dict] = []
    for key, entry in source.items():
        en_chars = len(entry.get("value", ""))
        if en_chars == 0:
            continue
        for locale, current in entry.get("translations", {}).items():
            if locale not in locales or (locale, key) in already:
                continue
            if len(current) < min_chars:
                continue
            ratio = len(current) / en_chars
            if ratio <= max_expansion:
                continue
            out.append({
                "locale": locale,
                "key": key,
                "severity": ratio_severity(ratio),
                "category": "length",
                "current": current,
                "back_translation": "",
                "issue": f"Translation is {ratio:.2f}× the English length ({len(current)} vs {en_chars} chars) — check for truncation/bloat.",
                "suggestion": "",
                "source": "ratio",
            })
    return out


def write_manifest(findings: list[dict], source: dict) -> None:
    # Re-translation is driven by the auditor's judgment ([llm]) only. The deterministic
    # [ratio] flag can't tell structurally-justified expansion (German compounding, agglutination,
    # script width) from avoidable bloat — on German alone it false-positives on standard words
    # like "Datenschutzerklärung" and "iCloud-Synchronisierung". Feeding those into the manifest
    # would re-translate correct strings and risk regressing them. Genuine length problems are
    # already captured as [llm] `length` findings (with a concrete suggestion); [ratio] stays
    # advisory in the human-readable report only.
    advisory = sum(1 for f in findings if f.get("source") == "ratio")
    findings = [f for f in findings if f.get("source") != "ratio"]
    if advisory:
        print(f"  ℹ Excluded {advisory} advisory [ratio] length flag(s) from the manifest "
              "(heuristic, not a verdict — see the report to eyeball them).")
    by_locale: dict[str, set[str]] = {}
    dropped: set[str] = set()
    for f in findings:
        if f["key"] not in source:  # e.g. an auditor-hallucinated key — don't emit a key with no source
            dropped.add(f["key"])
            continue
        by_locale.setdefault(f["locale"], set()).add(f["key"])
    if dropped:
        sample = sorted(dropped)[:5]
        print(f"  ⚠ {len(dropped)} flagged key(s) absent from audit_source.json — skipped: {sample}")
    manifest = {loc: sorted(keys) for loc, keys in sorted(by_locale.items()) if keys}
    if not manifest:
        print("\nNo [llm]-judged findings to re-translate — manifest not written "
              "(any flags at/above the threshold were advisory [ratio] only).")
        return
    union_keys = sorted({k for keys in by_locale.values() for k in keys})
    source_out = {}
    for k in union_keys:
        if k not in source:
            continue
        entry = {
            "comment": source[k].get("comment", ""),
            "formatSpecifiers": source[k].get("formatSpecifiers", []),
        }
        # Carry plural source as `plural` (not `value`) so plural keys re-translate correctly;
        # the translate pipeline keys off this exactly like extract.py --missing does.
        if "plural" in source[k]:
            entry["plural"] = source[k]["plural"]
        else:
            entry["value"] = source[k].get("value", "")
        source_out[k] = entry
    TRANSLATE_INPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with (TRANSLATE_INPUTS_DIR / "source.json").open("w", encoding="utf-8") as f:
        json.dump(source_out, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    with (TRANSLATE_INPUTS_DIR / "manifest.json").open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    pairs = sum(len(v) for v in manifest.values())
    print(
        f"\nWrote re-translation manifest: {len(union_keys)} key(s), {pairs} (key,locale) pair(s) "
        f"across {len(manifest)} locale(s) → {TRANSLATE_INPUTS_DIR}/"
        "\n  Next: run the translate-new-strings flow from step 2 (dispatch_prompts.py …)."
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--min-severity", choices=["high", "medium", "low"], default="low")
    parser.add_argument("--max-expansion", type=float, default=1.4,
                        help="[ratio] length-flag threshold: current/English char ratio (default 1.4).")
    parser.add_argument("--min-chars", type=int, default=20,
                        help="[ratio] length flag ignores translations shorter than this (default 20); "
                             "short strings have unstable ratios and rarely truncate.")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--write-manifest", action="store_true")
    parser.add_argument("locales", nargs="*", help="Locales to report (default: all in locales.py).")
    args = parser.parse_args(argv)

    locales = args.locales if args.locales else LOCALES
    threshold = SEVERITY_RANK[args.min_severity]

    source: dict = {}
    if AUDIT_SOURCE_PATH.exists():
        with AUDIT_SOURCE_PATH.open(encoding="utf-8") as f:
            source = json.load(f)
    elif args.write_manifest:
        print(f"ERROR: --write-manifest needs {AUDIT_SOURCE_PATH} (run audit_extract.py).", file=sys.stderr)
        return 2

    all_findings: list[dict] = []
    summaries: dict[str, str] = {}
    load_states: dict[str, str] = {}
    for locale in locales:
        findings, summary, state = load_findings(locale)
        load_states[locale] = state
        if summary:
            summaries[locale] = summary
        all_findings.extend(findings)

    if source:
        all_findings.extend(
            deterministic_length_findings(source, locales, all_findings, args.max_expansion, args.min_chars)
        )

    # Apply the severity threshold to everything we report / count / manifest.
    kept = [f for f in all_findings if SEVERITY_RANK[f["severity"]] >= threshold]
    kept.sort(key=lambda f: (-SEVERITY_RANK[f["severity"]], f["locale"], f["key"]))

    if args.json:
        print(json.dumps({
            "min_severity": args.min_severity,
            "max_expansion": args.max_expansion,
            "counts": _counts(kept),
            "load_states": load_states,
            "summaries": summaries,
            "findings": kept,
        }, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        _print_report(kept, summaries, load_states, locales, args)

    if args.write_manifest:
        if kept:
            write_manifest(kept, source)
        else:
            print("\nNo findings at/above the threshold — nothing to write to the manifest.")

    return 1 if kept else 0


def _counts(findings: list[dict]) -> dict:
    out = {"total": len(findings), "by_severity": {}, "by_category": {}, "by_source": {}}
    for f in findings:
        out["by_severity"][f["severity"]] = out["by_severity"].get(f["severity"], 0) + 1
        out["by_category"][f["category"]] = out["by_category"].get(f["category"], 0) + 1
        out["by_source"][f["source"]] = out["by_source"].get(f["source"], 0) + 1
    return out


def _print_report(findings: list[dict], summaries: dict, load_states: dict, locales: list, args) -> None:
    missing = [loc for loc in locales if load_states.get(loc) == "missing"]
    bad = [loc for loc in locales if load_states.get(loc) in ("badjson", "empty")]
    if missing:
        print(f"⚠ No audit output yet for {len(missing)} locale(s): {', '.join(missing)}")
    if bad:
        print(f"⚠ Unreadable/empty output for: {', '.join(bad)} (re-dispatch these)")

    if not findings:
        print(f"\n✓ No findings at/above severity '{args.min_severity}'. Clean. ✓")
        return

    current_sev = None
    for f in findings:
        if f["severity"] != current_sev:
            current_sev = f["severity"]
            print(f"\n{'=' * 6} {current_sev.upper()} {'=' * 6}")
        tag = f"[{f['source']}]"
        print(f"\n■ {f['locale']:<8} {f['key']}  ({f['category']}) {tag}")
        print(f"    current:  {f['current']}")
        if f["back_translation"]:
            print(f"    back:     {f['back_translation']}")
        if f["issue"]:
            print(f"    issue:    {f['issue']}")
        if f["suggestion"]:
            print(f"    suggest:  {f['suggestion']}")

    c = _counts(findings)
    print(f"\n{'-' * 60}")
    print(f"Summary: {c['total']} finding(s) at/above '{args.min_severity}' — "
          f"by severity {c['by_severity']} · by category {c['by_category']} · by source {c['by_source']}")
    if summaries:
        print("\nPer-locale auditor summaries:")
        for loc in sorted(summaries):
            print(f"  [{loc}] {summaries[loc]}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
