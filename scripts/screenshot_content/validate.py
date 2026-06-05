#!/usr/bin/env python3
"""
Validate per-storefront screenshot demo-content JSON against the source structure.

Checks each tmp/screenshot-content-outputs/{storefront}.json:
  1. Parses as JSON with a non-empty `budgets` array of at most MAX_BUDGETS.
  2. Includes the mandatory `everyday-food` budget.
  3. For every budget, the STRUCTURAL fields match the source budget of the same
     role: period, startOffsetDays, isCarryOverEnabled, expense count, and each
     expense's daysAgo (these drive the screenshot story and must be preserved).
  4. CONTENT is well-formed: non-empty short name, a single emoji icon, a 3-letter
     currency code, and allocation/expense amounts that parse as non-negative
     decimals within the currency's permitted decimal places (0 for JPY/KRW/…).
  5. At least one carry-over-enabled daily/weekly/biweekly budget has a completed
     prior period (startOffsetDays >= period length) so a carry-over chip shows.
  6. No single expense exceeds its budget's allocation (avoids an obvious deficit).
  7. No unexpected top-level keys (besides `budgets` and `_questions`).

States per storefront: PASS / WARN / PENDING (no output yet) / FAIL.
Exits 0 only if no FAIL and no PENDING (warnings don't fail).

Usage:
  python3 scripts/screenshot_content/validate.py [--subset] [--json] [storefront ...]
  # --subset: silently skip storefronts that have no output file yet (partial runs).
"""

from __future__ import annotations

import argparse
import json
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Tuple

sys.path.insert(0, str(Path(__file__).parent))
from content_locales import (  # noqa: E402
    INPUTS_DIR,
    MAX_BUDGETS,
    OUTPUTS_DIR,
    REQUIRED_ROLES,
    STOREFRONT_LOCALES,
    VALID_PERIODS,
    currency_decimals,
)

SOURCE_PATH = INPUTS_DIR / "source.json"
NAME_MAX_CHARS = 24
PERIOD_DAYS = {"daily": 1, "weekly": 7, "biweekly": 14, "monthly": 28, "specificDates": 1}


def _decimal_ok(value, max_decimals: int) -> Tuple[bool, str]:
    if not isinstance(value, str):
        return False, f"amount must be a JSON string (got {type(value).__name__})"
    try:
        dec = Decimal(value)
    except (InvalidOperation, ValueError):
        return False, f"amount {value!r} is not a valid number"
    if dec < 0:
        return False, f"amount {value!r} is negative"
    exponent = -dec.as_tuple().exponent
    if exponent > max_decimals:
        return False, f"amount {value!r} has more than {max_decimals} decimal place(s)"
    return True, ""


def _is_single_emoji(icon) -> bool:
    if not isinstance(icon, str) or not icon.strip():
        return False
    # Reject plain ASCII / latin letters; accept short non-ASCII (emoji, possibly
    # with a variation selector or ZWJ). Keep the grapheme short.
    if any(ord(ch) < 0x2190 for ch in icon if ch.isalnum()):
        return False
    return len(icon) <= 8


def validate_storefront(storefront: str, source_by_role: dict, subset: bool) -> Tuple[list, list, str]:
    errors: list[str] = []
    warnings: list[str] = []
    path = OUTPUTS_DIR / f"{storefront}.json"

    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        if subset:
            return [], [], "skipped (no output file)"
        return [], [], "no output file yet"

    try:
        out = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"[{storefront}] invalid JSON: {exc}"], [], ""

    extra = set(out.keys()) - {"budgets", "_questions"}
    if extra:
        errors.append(f"[{storefront}] unexpected top-level key(s): {sorted(extra)}")

    budgets = out.get("budgets")
    if not isinstance(budgets, list) or not budgets:
        return [f"[{storefront}] missing/empty 'budgets' array"], warnings, ""
    if len(budgets) > MAX_BUDGETS:
        errors.append(f"[{storefront}] {len(budgets)} budgets exceeds max of {MAX_BUDGETS}")

    roles_present = {b.get("role") for b in budgets}
    for role in REQUIRED_ROLES:
        if role not in roles_present:
            errors.append(f"[{storefront}] missing required budget role {role!r}")

    currencies = set()
    has_carryover_chip = False

    for b in budgets:
        role = b.get("role")
        src = source_by_role.get(role)
        tag = f"[{storefront}] budget {role!r}"
        if src is None:
            errors.append(f"{tag}: unknown role (not in source)")
            continue

        # Structural fields must match the source exactly.
        for field in ("period", "startOffsetDays", "isCarryOverEnabled"):
            if b.get(field) != src.get(field):
                errors.append(f"{tag}: {field} changed (got {b.get(field)!r}, expected {src.get(field)!r})")

        period = b.get("period")
        if period not in VALID_PERIODS:
            errors.append(f"{tag}: invalid period {period!r}")

        # Content fields.
        name = b.get("name")
        if not isinstance(name, str) or not name.strip():
            errors.append(f"{tag}: empty name")
        elif len(name) > NAME_MAX_CHARS:
            warnings.append(f"{tag}: name {len(name)} chars may truncate on the list row")

        if not _is_single_emoji(b.get("icon")):
            errors.append(f"{tag}: icon must be a single emoji (got {b.get('icon')!r})")

        currency = b.get("currencyCode")
        if not (isinstance(currency, str) and len(currency) == 3 and currency.isupper()):
            errors.append(f"{tag}: currencyCode must be a 3-letter ISO code (got {currency!r})")
            continue
        currencies.add(currency)
        max_dec = currency_decimals(currency)

        alloc_ok, alloc_msg = _decimal_ok(b.get("allocation"), max_dec)
        if not alloc_ok:
            errors.append(f"{tag}: allocation {alloc_msg}")
        allocation = Decimal(b["allocation"]) if alloc_ok else None

        src_expenses = src.get("expenses", [])
        out_expenses = b.get("expenses")
        if not isinstance(out_expenses, list) or len(out_expenses) != len(src_expenses):
            errors.append(
                f"{tag}: expense count changed (got "
                f"{len(out_expenses) if isinstance(out_expenses, list) else 'n/a'}, "
                f"expected {len(src_expenses)})"
            )
        else:
            for i, (exp, src_exp) in enumerate(zip(out_expenses, src_expenses)):
                if exp.get("daysAgo") != src_exp.get("daysAgo"):
                    errors.append(f"{tag} expense[{i}]: daysAgo changed (must preserve source)")
                ename = exp.get("name")
                if not isinstance(ename, str) or not ename.strip():
                    errors.append(f"{tag} expense[{i}]: empty name")
                amt_ok, amt_msg = _decimal_ok(exp.get("amount"), max_dec)
                if not amt_ok:
                    errors.append(f"{tag} expense[{i}]: {amt_msg}")
                elif allocation is not None and Decimal(exp["amount"]) > allocation:
                    errors.append(
                        f"{tag} expense[{i}]: amount {exp['amount']} exceeds allocation "
                        f"{b['allocation']} (would read as overspend)"
                    )

        if (
            b.get("isCarryOverEnabled") is True
            and period in ("daily", "weekly", "biweekly")
            and isinstance(b.get("startOffsetDays"), int)
            and b["startOffsetDays"] >= PERIOD_DAYS.get(period, 1)
        ):
            has_carryover_chip = True

    if len(currencies) > 1:
        warnings.append(f"[{storefront}] mixed currencies {sorted(currencies)} (expected one per market)")
    if not has_carryover_chip:
        errors.append(f"[{storefront}] no carry-over-enabled budget with a completed prior period (chip won't show)")

    return errors, warnings, ""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--subset", action="store_true", help="Skip storefronts with no output file yet.")
    parser.add_argument("--json", action="store_true", help="Emit a machine-readable JSON summary.")
    parser.add_argument("storefronts", nargs="*", help="Storefronts to validate (default: all).")
    args = parser.parse_args(argv)

    if not SOURCE_PATH.exists():
        print(f"ERROR: source not found at {SOURCE_PATH}. Run extract.py first.", file=sys.stderr)
        return 1

    source = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    source_by_role = {b["role"]: b for b in source["budgets"]}

    storefronts = args.storefronts if args.storefronts else STOREFRONT_LOCALES
    results: dict[str, dict] = {}
    fail = pending = 0

    for storefront in storefronts:
        errors, warnings, note = validate_storefront(storefront, source_by_role, args.subset)
        if errors:
            status = "FAIL"
            fail += 1
        elif note and not args.subset:
            status = "PENDING"
            pending += 1
        elif note:
            status = "SKIP"
        elif warnings:
            status = "WARN"
        else:
            status = "PASS"
        results[storefront] = {"status": status, "errors": errors, "warnings": warnings, "note": note}

    if args.json:
        summary = {
            "pass": [s for s, r in results.items() if r["status"] in ("PASS", "WARN")],
            "pending": [s for s, r in results.items() if r["status"] == "PENDING"],
            "fail": [s for s, r in results.items() if r["status"] == "FAIL"],
            "results": results,
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
        return 1 if (fail or pending) else 0

    print(f"\n{'Storefront':<12} {'Status':<8} Detail")
    print("-" * 60)
    for storefront in storefronts:
        r = results[storefront]
        detail = r["note"] or (f"{len(r['errors'])} error(s)" if r["errors"] else f"{len(r['warnings'])} warning(s)" if r["warnings"] else "")
        print(f"{storefront:<12} {r['status']:<8} {detail}")
        for err in r["errors"]:
            print(f"  ✗ {err}")
        for warn in r["warnings"]:
            print(f"  ⚠ {warn}")

    print()
    if fail or pending:
        print(f"NOT READY: {fail} FAIL, {pending} PENDING of {len(storefronts)} storefront(s). Re-dispatch those, then re-validate.")
        return 1
    print(f"PASSED: all {len(storefronts)} checked storefront(s) passed validation.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
