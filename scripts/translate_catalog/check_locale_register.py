#!/usr/bin/env python3
"""
Guard for locale_register.py consolidation (issue #173).

Asserts:
  1. Every runtime locale in locales.LOCALES has an explicit REGISTER entry.
  2. Composed REGIONAL_NOTES match the pre-consolidation catalog notes byte-for-byte.
  3. Composed CULTURAL_NOTES match the pre-consolidation metadata notes byte-for-byte.

Run from repo root:
  python3 scripts/translate_catalog/check_locale_register.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

CATALOG_DIR = Path(__file__).resolve().parent
REPO_ROOT = CATALOG_DIR.parents[1]
METADATA_DIR = REPO_ROOT / "scripts" / "translate_metadata"

import importlib.util


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


_catalog = _load_module("catalog_dispatch", CATALOG_DIR / "dispatch_prompts.py")
_metadata = _load_module("metadata_dispatch", METADATA_DIR / "dispatch_prompts.py")
_locales = _load_module("catalog_locales", CATALOG_DIR / "locales.py")
_register = _load_module("locale_register", CATALOG_DIR / "locale_register.py")
_meta_locales = _load_module("metadata_locales", METADATA_DIR / "metadata_locales.py")

REGIONAL_NOTES = _catalog.REGIONAL_NOTES
CULTURAL_NOTES = _metadata.CULTURAL_NOTES
REGISTER = _register.REGISTER
LOCALES = _locales.LOCALES
STOREFRONT_LOCALES = _meta_locales.STOREFRONT_LOCALES
STOREFRONT_TO_RUNTIME = _meta_locales.STOREFRONT_TO_RUNTIME


def _load_expected_dict(module_path: str, name: str) -> dict[str, str]:
    text = subprocess.check_output(["git", "show", f"main:{module_path}"], text=True)
    ns: dict = {"__file__": module_path, "__name__": "expected_snapshot"}
    exec(text, ns)  # noqa: S102 — trusted repo snapshot
    return ns[name]


def main() -> int:
    errors: list[str] = []

    missing_register = [loc for loc in LOCALES if loc not in REGISTER]
    if missing_register:
        errors.append(
            f"REGISTER missing {len(missing_register)} locale(s): {missing_register}"
        )

    for storefront in STOREFRONT_LOCALES:
        runtime = STOREFRONT_TO_RUNTIME[storefront]
        if runtime not in REGISTER:
            errors.append(
                f"STOREFRONT {storefront} maps to runtime {runtime} with no REGISTER entry"
            )

    try:
        expected_regional = _load_expected_dict(
            "scripts/translate_catalog/dispatch_prompts.py", "REGIONAL_NOTES"
        )
        expected_cultural = _load_expected_dict(
            "scripts/translate_metadata/dispatch_prompts.py", "CULTURAL_NOTES"
        )
    except subprocess.CalledProcessError as exc:
        errors.append(f"Could not load expected notes from main: {exc}")
        expected_regional = {}
        expected_cultural = {}

    for locale, expected in sorted(expected_regional.items()):
        actual = REGIONAL_NOTES.get(locale)
        if actual != expected:
            errors.append(f"REGIONAL_NOTES[{locale!r}] drifted from main")

    for storefront, expected in sorted(expected_cultural.items()):
        actual = CULTURAL_NOTES.get(storefront)
        if actual != expected:
            errors.append(f"CULTURAL_NOTES[{storefront!r}] drifted from main")

    if errors:
        print("check_locale_register: FAIL", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(
        f"check_locale_register: OK — {len(REGISTER)} register entries, "
        f"{len(REGIONAL_NOTES)} catalog notes, {len(CULTURAL_NOTES)} metadata notes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
