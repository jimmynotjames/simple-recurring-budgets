#!/usr/bin/env python3
"""Render an app-target line-coverage report from `xccov view --report --json`.

Reads the xccov JSON on stdin (piped by scripts/coverage.sh) and prints:
  - overall app-target line coverage, raw and after exclusions
  - a per-top-level-folder breakdown
  - the per-file list sorted ascending, flagging 0%-covered files

Report-only by design (audit 2026-06-10, A1): exits 0 regardless of the
numbers; exits 1 only if the app target can't be found in the JSON.

Exclusions mirror the audit's "reasonable to skip" set: preview fixtures and
screenshot/debug tooling that ship in the app target but are never user-facing.
"""

import json
import sys

APP_TARGET_SUFFIX = "simple-recurring-budgets.app"

# Path substrings excluded from the headline number (still listed at the end).
EXCLUDED_PATH_PARTS = [
    "/Previews/",
    "/DebugData.swift",
    "/TestDynamicTypeOverride.swift",
]

# Repo source root used to derive folder names and short display paths.
SOURCE_ROOT_MARKER = "/simple-recurring-budgets/"


def is_excluded(path: str) -> bool:
    return any(part in path for part in EXCLUDED_PATH_PARTS)


def short_path(path: str) -> str:
    idx = path.rfind(SOURCE_ROOT_MARKER)
    return path[idx + len(SOURCE_ROOT_MARKER):] if idx != -1 else path


def top_folder(path: str) -> str:
    rel = short_path(path)
    return rel.split("/", 1)[0] if "/" in rel else "(root)"


def pct(covered: int, executable: int) -> str:
    if executable == 0:
        return "  n/a"
    return f"{100.0 * covered / executable:5.1f}%"


def main() -> int:
    report = json.load(sys.stdin)

    target = next(
        (t for t in report.get("targets", []) if t.get("name", "").endswith(APP_TARGET_SUFFIX)),
        None,
    )
    if target is None:
        names = ", ".join(t.get("name", "?") for t in report.get("targets", []))
        print(f"coverage: app target '{APP_TARGET_SUFFIX}' not in report (targets: {names})", file=sys.stderr)
        return 1

    files = target.get("files", [])
    included = [f for f in files if not is_excluded(f["path"])]
    excluded = [f for f in files if is_excluded(f["path"])]

    def totals(file_list):
        return (
            sum(f["coveredLines"] for f in file_list),
            sum(f["executableLines"] for f in file_list),
        )

    raw_cov, raw_exec = totals(files)
    inc_cov, inc_exec = totals(included)

    print(f"App-target line coverage ({len(files)} files)")
    print(f"  raw:        {pct(raw_cov, raw_exec)}  ({raw_cov}/{raw_exec} lines)")
    print(f"  effective:  {pct(inc_cov, inc_exec)}  ({inc_cov}/{inc_exec} lines)  — excluding {len(excluded)} previews/tooling files")

    print("\nBy folder (exclusions applied):")
    folders: dict[str, list] = {}
    for f in included:
        folders.setdefault(top_folder(f["path"]), []).append(f)
    for name in sorted(folders, key=lambda n: -totals(folders[n])[1]):
        cov, ex = totals(folders[name])
        print(f"  {pct(cov, ex)}  {name}/  ({len(folders[name])} files, {ex} lines)")

    print("\nFiles, least-covered first (exclusions applied):")
    for f in sorted(included, key=lambda f: (f["lineCoverage"], -f["executableLines"])):
        flag = "  ← 0%" if f["coveredLines"] == 0 and f["executableLines"] > 0 else ""
        print(f"  {pct(f['coveredLines'], f['executableLines'])}  {short_path(f['path'])}{flag}")

    if excluded:
        print("\nExcluded from the numbers above (previews/tooling):")
        for f in sorted(excluded, key=lambda f: short_path(f["path"])):
            print(f"  {pct(f['coveredLines'], f['executableLines'])}  {short_path(f['path'])}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
