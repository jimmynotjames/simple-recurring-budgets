#!/usr/bin/env python3
"""
Turn the errors in an xcodebuild log into GitHub feedback.

ci.yml's `build` job tees `xcodebuild build-for-testing` into a log. When that step
fails, this script reads the log and emits:

  1. One `::error file=...,line=...,col=...::msg` annotation per distinct compiler
     error, so it shows on the PR's Files tab. Errors without a file (linker,
     `xcodebuild: error:`, missing build inputs) become plain `::error::` lines.
  2. A Markdown list of every error in the job's Step Summary.
  3. The same list in the step log, under a "Compile errors" heading, so the full
     raw log above it doesn't have to be searched.

It only reports; it always exits 0 (the build step already failed the job).
Without GITHUB_ACTIONS set it prints the plain list only, for local use.

Usage:
  python3 scripts/ci/xcode_errors.py <xcodebuild.log>
"""

from __future__ import annotations

import os
import re
import sys

FILE_ERROR = re.compile(
    r"^(?P<file>/[^:\n]+):(?P<line>\d+):(?:(?P<col>\d+):)? (?:fatal )?error: (?P<msg>.+)$"
)
OTHER_ERROR = re.compile(r"^(?:[\w.-]+: )?(?:fatal )?error: (?P<msg>.+)$|^(?P<undef>Undefined symbols? .+)$")
MAX_LISTED = 100


def _escape_data(s: str) -> str:
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _escape_prop(s: str) -> str:
    return _escape_data(s).replace(":", "%3A").replace(",", "%2C")


def parse(text: str, workspace: str) -> list[dict]:
    seen: set[tuple] = set()
    errors: list[dict] = []
    prefix = workspace.rstrip("/") + "/" if workspace else ""
    lines = text.splitlines()
    for i, raw in enumerate(lines):
        line = raw.strip()
        m = FILE_ERROR.match(line)
        if m:
            path = m["file"]
            if prefix and path.startswith(prefix):
                path = path[len(prefix) :]
            err = {"file": path, "line": int(m["line"]), "col": int(m["col"]) if m["col"] else None, "msg": m["msg"]}
        else:
            m = OTHER_ERROR.match(line)
            if not m:
                continue
            msg = line
            if m["undef"]:
                # The linker lists the missing symbols on the indented lines that follow.
                detail = [ln.strip() for ln in lines[i + 1 : i + 7] if ln[:1].isspace() and ln.strip()]
                msg = " ".join([line, *detail])
            err = {"file": None, "line": None, "col": None, "msg": msg}
        key = (err["file"], err["line"], err["col"], err["msg"])
        if key not in seen:
            seen.add(key)
            errors.append(err)
    return errors


def location(err: dict) -> str:
    if not err["file"]:
        return ""
    loc = f"{err['file']}:{err['line']}"
    return loc + (f":{err['col']}" if err["col"] else "")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 0
    try:
        with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        print(f"::warning::Could not read {sys.argv[1]}: {e}")
        return 0

    errors = parse(text, os.environ.get("GITHUB_WORKSPACE", ""))
    in_ci = bool(os.environ.get("GITHUB_ACTIONS"))

    print(f"Compile errors ({len(errors)}):")
    for err in errors:
        loc = location(err)
        print(f"  {loc}: {err['msg']}" if loc else f"  {err['msg']}")
    if not errors:
        print("  None matched. Search the raw log above for 'error:' or 'BUILD FAILED'.")

    if not in_ci:
        return 0

    for err in errors:
        if err["file"]:
            props = f"file={_escape_prop(err['file'])},line={err['line']}"
            if err["col"]:
                props += f",col={err['col']}"
            print(f"::error {props},title=Compile error::{_escape_data(err['msg'])}")
        else:
            print(f"::error title=Build error::{_escape_data(err['msg'])}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        lines = ["### Compile errors", ""]
        if not errors:
            lines.append("The build failed, but no `error:` lines matched. See the **Build for testing** step log.")
        for err in errors[:MAX_LISTED]:
            loc = location(err)
            lines.append(f"- `{loc}`: {err['msg']}" if loc else f"- {err['msg']}")
        if len(errors) > MAX_LISTED:
            lines.append(f"- …and {len(errors) - MAX_LISTED} more in the step log.")
        with open(summary, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
