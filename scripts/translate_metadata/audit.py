#!/usr/bin/env python3
"""
Audit the per-storefront transcreation outputs in tmp/metadata-outputs/.

This is the inspection + escalation tool for the metadata pipeline. It exists so
the skill (and a human) never need ad-hoc `python3 -c`, `wc`, `cat`, or `jq` to
answer "what did the fan-out produce, what's over the limit, and what did the
subagents flag for me?" — all of which are non-allowlistable and prompt.

For every target storefront it reports, per field:
  - the transcreated value (optionally elided),
  - its character count vs. the App Store Connect limit, and an OVER flag,
and per storefront an overall status:
  - PASS    — present, all fields within limits
  - OVER    — present but at least one field exceeds its limit (re-dispatch)
  - PENDING — no output yet, or an empty stub (dispatch / re-dispatch)
It also collects every `_questions` entry the subagents attached, across all
locales, into a single consolidated batch — the one human checkpoint.

Usage:
  python3 scripts/translate_metadata/audit.py [--questions] [--full] [--json] [storefront ...]

  (default)     human-readable per-storefront field/char-count table + a summary
                line + the consolidated questions batch.
  --questions   ONLY print the consolidated `_questions` batch (and nothing else).
                Use this to drive the Step 4a human checkpoint.
  --full        print full field values (default elides long fields to one line).
  --json        emit a machine-readable JSON summary instead of the table.
  storefront…   restrict to the given storefronts (default: all targets).

Exit code: 0 if every audited storefront is PASS; 1 otherwise (OVER or PENDING),
so it can gate an autonomous loop the same way validate.py does.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUTS_DIR = REPO_ROOT / "tmp" / "metadata-outputs"

sys.path.insert(0, str(Path(__file__).parent))
from metadata_locales import FIELD_LIMITS, STOREFRONT_LOCALES, TRANSLATABLE_FIELDS  # noqa: E402

_ELIDE_AT = 70


def load_output(storefront: str) -> tuple[dict | None, str]:
    """Return (parsed_dict_or_None, state). state in {ok, pending, badjson}."""
    path = OUTPUTS_DIR / f"{storefront}.json"
    if not path.exists():
        return None, "pending"
    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return None, "pending"
    try:
        return json.loads(raw), "ok"
    except json.JSONDecodeError:
        return None, "badjson"


def audit_storefront(storefront: str) -> dict:
    out, state = load_output(storefront)
    info: dict = {"storefront": storefront, "fields": {}, "questions": [], "status": "PENDING"}

    if state == "pending":
        info["status"] = "PENDING"
        return info
    if state == "badjson":
        info["status"] = "FAIL"
        info["error"] = "invalid JSON"
        return info

    assert out is not None
    any_over = False
    for field in TRANSLATABLE_FIELDS:
        if field not in out:
            continue
        value = out[field]
        if isinstance(value, dict):
            value = value.get("value", "")
        if not isinstance(value, str):
            value = str(value)
        limit = FIELD_LIMITS.get(field)
        over = bool(limit and len(value) > limit)
        any_over = any_over or over
        info["fields"][field] = {"value": value, "len": len(value), "limit": limit, "over": over}

    raw_questions = out.get("_questions", [])
    if isinstance(raw_questions, list):
        for q in raw_questions:
            if isinstance(q, dict):
                info["questions"].append({**q, "storefront": storefront})

    info["status"] = "OVER" if any_over else "PASS"
    return info


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--questions", action="store_true", help="Only print the consolidated _questions batch.")
    parser.add_argument("--full", action="store_true", help="Print full field values (do not elide long fields).")
    parser.add_argument("--json", action="store_true", help="Emit a machine-readable JSON summary.")
    parser.add_argument("storefronts", nargs="*", help="Storefronts to audit (default: all targets).")
    args = parser.parse_args(argv)

    storefronts = args.storefronts if args.storefronts else STOREFRONT_LOCALES
    audits = [audit_storefront(s) for s in storefronts]
    all_questions = [q for a in audits for q in a["questions"]]

    if args.json:
        print(json.dumps(
            {
                "summary": {
                    "pass": [a["storefront"] for a in audits if a["status"] == "PASS"],
                    "over": [a["storefront"] for a in audits if a["status"] == "OVER"],
                    "pending": [a["storefront"] for a in audits if a["status"] == "PENDING"],
                    "fail": [a["storefront"] for a in audits if a["status"] == "FAIL"],
                },
                "questions": all_questions,
                "audits": audits,
            },
            ensure_ascii=False, indent=2, sort_keys=True,
        ))
        return 0 if all(a["status"] == "PASS" for a in audits) else 1

    if args.questions:
        return _print_questions(all_questions)

    # Full human-readable report.
    for a in audits:
        s = a["storefront"]
        if a["status"] == "PENDING":
            print(f"\n■ {s:<10} PENDING — no output yet (dispatch this storefront)")
            continue
        if a["status"] == "FAIL":
            print(f"\n■ {s:<10} FAIL — {a.get('error', 'invalid output')}")
            continue
        flag = "OVER ⚠" if a["status"] == "OVER" else "PASS"
        print(f"\n■ {s:<10} {flag}")
        for field, fi in a["fields"].items():
            mark = "  OVER" if fi["over"] else ""
            limit = fi["limit"] if fi["limit"] is not None else "-"
            value = fi["value"]
            if not args.full and len(value) > _ELIDE_AT:
                value = value[:_ELIDE_AT] + "…"
            value = value.replace("\n", "⏎")
            print(f"    {field:<17} {fi['len']:>4}/{limit!s:<5}{mark:<6} {value}")

    n_pass = sum(1 for a in audits if a["status"] == "PASS")
    n_over = sum(1 for a in audits if a["status"] == "OVER")
    n_pending = sum(1 for a in audits if a["status"] == "PENDING")
    n_fail = sum(1 for a in audits if a["status"] == "FAIL")
    print(f"\nSummary: {n_pass} PASS, {n_over} OVER, {n_pending} PENDING, {n_fail} FAIL "
          f"(of {len(audits)} storefront(s)).")

    _print_questions(all_questions)
    return 0 if (n_over == n_pending == n_fail == 0) else 1


def _print_questions(all_questions: list[dict]) -> int:
    if not all_questions:
        print("\nNo content questions raised by any locale. ✓ (expected case — nothing to escalate)")
        return 0
    print(f"\n=== {len(all_questions)} content question(s) raised — the human checkpoint ===")
    for q in all_questions:
        sf = q.get("storefront", "?")
        field = q.get("field", "?")
        issue = q.get("issue", "")
        decision = q.get("decision", "")
        print(f"\n[{sf}] field={field}")
        print(f"  issue:    {issue}")
        print(f"  default:  {decision}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
