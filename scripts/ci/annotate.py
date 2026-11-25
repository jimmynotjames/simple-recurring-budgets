#!/usr/bin/env python3
"""Run a checker with `--json` and report its findings to GitHub Actions.

Emits `::error`/`::warning` annotations (with file/line where the finding has them) and a
Markdown block in $GITHUB_STEP_SUMMARY. Exits with the wrapped command's exit code, so the
step passes or fails exactly as the checker does. Output that isn't JSON passes through.

Usage:
  python3 scripts/ci/annotate.py --name <check-name> -- <command> [args...]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


def _finding_line(f: dict) -> str:
    if "file" in f and "line" in f:
        return f"{f['file']}:{f['line']}: {f.get('message', '')}".rstrip(": ")
    if "locale" in f and "key" in f:
        message = f.get("message", "")
        return f"[{f['locale']}] {f['key']}" + (f": {message}" if message else "")
    if "first" in f and "second" in f:
        # distinct_pairs.py
        return f"[{f.get('locale', '?')}] {f['first']} = {f['second']}: {f.get('value', '')!r}"
    if "field" in f:
        return f"{f.get('field')}: {f.get('kind', '')} {f.get('match', '')!r}"
    if "message" in f:
        return f["message"]
    return json.dumps(f, ensure_ascii=False)


def normalize(payload: dict | list) -> list[dict]:
    """Flatten a checker's --json payload into a list of finding dicts."""
    if isinstance(payload, list):
        # distinct_pairs.py: [{...}, ...]
        return [f if isinstance(f, dict) else {"message": str(f)} for f in payload]
    if "errors" in payload or "warnings" in payload:
        # check_source_strings.py: {"errors": [...], "warnings": [...]}
        # check_doc_pointers.py: {"errors": [...]}
        out = []
        for kind, severity in (("errors", "error"), ("warnings", "warning")):
            for f in payload.get(kind, []):
                out.append({**f, "severity": severity})
        return out
    if "issues" in payload:
        # check_translations.py / check_metadata.py: {"issues": ["free text", ...]}
        return [{"message": line} for line in payload["issues"]]
    if "findings" in payload:
        # plural_completeness.py / untranslated_copies.py / check_source_voice.py
        return payload["findings"]
    return []


def emit_annotations(findings: list[dict]) -> None:
    for f in findings:
        severity = f.get("severity", "error")
        message = _finding_line(f)
        if "file" in f and "line" in f:
            print(f"::{severity} file={f['file']},line={f['line']}::{message}")
        else:
            print(f"::{severity}::{message}")


def write_summary(name: str, passed: bool, findings: list[dict]) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    lines = [f"### {name} — {'✅ passed' if passed else '❌ failed'}", ""]
    if findings:
        lines.append(f"{len(findings)} finding(s):")
        lines.append("")
        for f in findings[:50]:
            lines.append(f"- {_finding_line(f)}")
        if len(findings) > 50:
            lines.append(f"- …and {len(findings) - 50} more (see job log)")
    lines.append("")
    with open(summary_path, "a", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--name", required=True, help="Check name (used in the summary heading).")
    parser.add_argument("command", nargs=argparse.REMAINDER,
                         help="Command to run, e.g. -- python3 scripts/check_translations.py")
    args = parser.parse_args(argv)

    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("annotate.py: no command given (expected `-- <command> [args...]`)", file=sys.stderr)
        return 2

    proc = subprocess.run([*command, "--json"], capture_output=True, text=True)
    passed = proc.returncode == 0

    try:
        findings = normalize(json.loads(proc.stdout))
    except json.JSONDecodeError:
        sys.stdout.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        return proc.returncode

    if findings:
        print(f"{args.name}: {len(findings)} finding(s):\n")
        for f in findings:
            print(f"  {_finding_line(f)}")
    elif passed:
        print(f"{args.name}: passed, no findings.")
    else:
        print(f"{args.name}: failed (exit {proc.returncode}) with no parsed findings.")
        sys.stderr.write(proc.stderr)

    emit_annotations(findings)
    write_summary(args.name, passed, findings)

    return proc.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
