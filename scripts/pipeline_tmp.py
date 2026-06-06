#!/usr/bin/env python3
"""
Inspect or clear the gitignored ``tmp/`` working directories used by the
localization fan-out pipelines (translate / metadata / screenshot-content /
their audits / the size-check). These dirs hold per-locale prompt and output
files.

Why this exists: the merge/validate steps read **every** file in an outputs dir,
not just the current manifest's. So leftover per-locale files from a previous run
silently contaminate a fresh run (re-merged, re-validated, or counted as
"already done"). Run ``status`` before starting a pipeline to spot stale
leftovers, ``clean`` to clear them, and ``clean`` again at the end to tidy up.

This script only ever touches the known ``tmp/`` subdirectories listed below
(all gitignored). It never deletes the directories themselves (so the pipelines'
``mkdir -p`` stays a no-op) and never touches the catalog, the metadata tree, the
ScreenshotSeeds catalog, or any committed file.

Usage:
  python3 scripts/pipeline_tmp.py status [GROUP ...]   # list files per dir
  python3 scripts/pipeline_tmp.py clean  [GROUP ...]   # delete files in the dirs

GROUPs (default: all):
  translate            in-app strings        (translate-new-strings skill)
  translate-audit      translation QA audit  (audit-translations skill)
  metadata             App Store metadata    (appstore-translate-metadata skill)
  screenshot-content   screenshot demo data  (appstore-screenshot-content skill)
  size-check           large-type captures   (translation-accessibility-size-check skill)
  all                  every group above
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TMP = REPO_ROOT / "tmp"

# Each group -> the tmp/ subdirectory names it owns. Keep in sync with the
# *_DIR constants in scripts/{translate_catalog,translate_audit,translate_metadata,
# screenshot_content}/*.py and translation-accessibility-size-check/run.sh.
GROUPS: dict[str, list[str]] = {
    "translate": [
        "translate-inputs",
        "translate-prompts",
        "translate-outputs",
        "glossary",
    ],
    "translate-audit": [
        "translate-audit-inputs",
        "translate-audit-prompts",
        "translate-audit-outputs",
    ],
    "metadata": [
        "metadata-inputs",
        "metadata-prompts",
        "metadata-outputs",
        "metadata-audit-prompts",
        "metadata-audit-outputs",
    ],
    "screenshot-content": [
        "screenshot-content-inputs",
        "screenshot-content-prompts",
        "screenshot-content-outputs",
    ],
    "size-check": [
        "loc-size-check",
    ],
}


def resolve_dirs(groups: list[str]) -> list[Path]:
    """Expand group names to deduped tmp/ directory paths, preserving order."""
    seen: set[str] = set()
    dirs: list[Path] = []
    for group in groups:
        for name in GROUPS[group]:
            if name not in seen:
                seen.add(name)
                dirs.append(TMP / name)
    return dirs


def cmd_status(dirs: list[Path]) -> int:
    total = 0
    for d in dirs:
        rel = d.relative_to(REPO_ROOT)
        if not d.exists():
            print(f"  (absent)  {rel}")
            continue
        files = sorted(p for p in d.iterdir() if p.is_file())
        total += len(files)
        print(f"  {len(files):>4} file(s)  {rel}" if files else f"     empty  {rel}")
    print(f"\n{total} stale file(s) total — run `clean` to clear." if total else "\nNo stale files; clean to start.")
    return 0


def cmd_clean(dirs: list[Path]) -> int:
    removed = 0
    for d in dirs:
        if not d.exists():
            continue
        for p in d.iterdir():
            if p.is_dir():
                shutil.rmtree(p)
            else:
                p.unlink()
            removed += 1
    print(f"Cleared {removed} item(s) across {len(dirs)} dir(s).")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("command", choices=["status", "clean"])
    parser.add_argument(
        "groups",
        nargs="*",
        help="Pipeline group(s) to act on. Default: all.",
    )
    args = parser.parse_args(argv)

    groups = args.groups or ["all"]
    if "all" in groups:
        groups = list(GROUPS)
    unknown = [g for g in groups if g not in GROUPS]
    if unknown:
        print(
            f"ERROR: unknown group(s): {unknown}. Valid: {list(GROUPS) + ['all']}",
            file=sys.stderr,
        )
        return 2

    dirs = resolve_dirs(groups)
    return cmd_status(dirs) if args.command == "status" else cmd_clean(dirs)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
