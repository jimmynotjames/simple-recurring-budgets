#!/usr/bin/env python3
"""
Sync Localizable.xcstrings with the strings the last `make build` extracted, as a build in Xcode does.

`xcodebuild` extracts every `String(localized:)` and `LocalizedStringResource` into `.stringsdata`
files but, unlike a build in Xcode, never merges them back into the catalog. This runs the same
merge (`xcstringstool sync`) on a copy, then writes the result in Xcode's byte format:

  - a changed `comment:` in Swift replaces the catalog's comment;
  - a key new in Swift is added with its English value;
  - a key no longer in Swift is marked `stale` (`make i18n-check` then fails until
    `remove_keys.py` drops it).

Translations and their states are never touched, so a comment-only change costs no re-translation.

Needs a current `make build`: it reads that build's derived data, not the Swift sources. Sources
under DesignExplorations/ (gitignored scratch) are left out, as in check_source_strings.py.

Usage:
  python3 scripts/translate_catalog/sync_catalog.py           # sync the catalog in place
  python3 scripts/translate_catalog/sync_catalog.py --check   # exit 1 if a sync would change it
  python3 scripts/translate_catalog/sync_catalog.py --format  # only rewrite in Xcode's byte format
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from paths import CATALOG_PATH, REPO_ROOT, SOURCE_DIR  # noqa: E402
from xcstrings_io import write_xcstrings, xcstrings_text  # noqa: E402

# `-derivedDataPath` and destination from scripts/build.sh.
STRINGSDATA_DIR = (
    REPO_ROOT / ".build" / "DerivedData" / "Build" / "Intermediates.noindex" / "simple-recurring-budgets.build"
    / "Debug-iphonesimulator" / "simple-recurring-budgets.build" / "Objects-normal" / "arm64"
)
WORK_DIR = REPO_ROOT / "tmp" / "catalog-sync"
EXCLUDED_DIR = SOURCE_DIR / "DesignExplorations"
GENERATED_STRING_SYMBOLS = "GeneratedStringSymbols_"


def select_stringsdata(stringsdata_dir: Path, source_dir: Path, excluded_dir: Path) -> tuple[list[Path], list[Path]]:
    """The `.stringsdata` files for current app sources, and the app sources that have none.

    Derived data keeps the file of a deleted or excluded Swift source; passing it on would keep that
    source's keys alive. So would the string symbols Xcode generates from the catalog itself, which
    Xcode's own sync leaves out too: a key dropped from Swift goes `stale` there.
    """
    sources = {p.resolve() for p in source_dir.rglob("*.swift") if not p.resolve().is_relative_to(excluded_dir.resolve())}
    selected, seen = [], set()
    for path in sorted(stringsdata_dir.glob("*.stringsdata")):
        if path.name.startswith(GENERATED_STRING_SYMBOLS):
            continue
        source = Path(json.loads(path.read_text(encoding="utf-8"))["source"])
        if source.is_absolute() and source.resolve().is_relative_to(source_dir.resolve()):
            if source.resolve() not in sources:
                continue
            seen.add(source.resolve())
        selected.append(path)
    return selected, sorted(sources - seen)


def synced_text() -> str:
    if not STRINGSDATA_DIR.is_dir():
        raise SystemExit(
            f"ERROR: {STRINGSDATA_DIR.relative_to(REPO_ROOT)} does not exist. Run `make build` first; if it "
            "has run, scripts/build.sh's derived data path, destination or ARCHS changed: update STRINGSDATA_DIR."
        )
    selected, unbuilt = select_stringsdata(STRINGSDATA_DIR, SOURCE_DIR, EXCLUDED_DIR)
    if unbuilt:
        names = ", ".join(str(p.relative_to(REPO_ROOT)) for p in unbuilt[:5])
        raise SystemExit(f"ERROR: no extracted strings for {len(unbuilt)} source(s) ({names}). Run `make build` first.")
    # xcstringstool matches each .stringsdata table to the catalog by file name, so the copy keeps it.
    shutil.rmtree(WORK_DIR, ignore_errors=True)
    WORK_DIR.mkdir(parents=True)
    work_copy = WORK_DIR / CATALOG_PATH.name
    shutil.copyfile(CATALOG_PATH, work_copy)
    subprocess.run(
        ["xcrun", "xcstringstool", "sync", str(work_copy), "--stringsdata", *map(str, selected)],
        check=True,
    )
    return xcstrings_text(json.loads(work_copy.read_text(encoding="utf-8")))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Exit 1 if a sync would change the catalog; write nothing.")
    mode.add_argument("--format", action="store_true", help="Rewrite in Xcode's byte format without syncing.")
    args = parser.parse_args(argv)

    current = CATALOG_PATH.read_text(encoding="utf-8")
    if args.format:
        write_xcstrings(json.loads(current), CATALOG_PATH)
        return 0

    synced = synced_text()
    if synced == current:
        print("sync_catalog: catalog matches the Swift sources.")
        return 0
    if args.check:
        before, after = json.loads(current)["strings"], json.loads(synced)["strings"]
        changed = sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))
        if changed:
            print(f"sync_catalog: a build in Xcode would change {len(changed)} key(s) in {CATALOG_PATH.name}:")
            for key in changed:
                print(f"  {key}")
        else:
            print(f"sync_catalog: {CATALOG_PATH.name} is not in Xcode's byte format.")
        print("Run `python3 scripts/translate_catalog/sync_catalog.py` and commit the result.")
        return 1
    CATALOG_PATH.write_text(synced, encoding="utf-8")
    print(f"sync_catalog: synced {CATALOG_PATH.name}; review the diff.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
