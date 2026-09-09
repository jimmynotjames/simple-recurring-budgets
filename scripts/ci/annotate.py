#!/usr/bin/env python3
"""
Shared CI feedback helper for the mechanical per-PR gates.

Wraps a checker script's `--json` output mode and turns it into three things
GitHub Actions understands natively, so a first-time CI reader gets in-context
feedback instead of "go read the raw log":

  1. GitHub annotations (`::error file=...,line=...::msg` / `::warning ...`)
     for findings that carry a real file/line.
  2. A Markdown block appended to the job's Step Summary
     ($GITHUB_STEP_SUMMARY), so the failure is scannable without opening logs.
  3. A `<name>_passed=true|false` line appended to $GITHUB_OUTPUT, so the
     `pr-summary` job can read every gate's result via `needs.<job>.outputs`
     and assemble one consolidated PR comment.

The wrapped command's own exit code is this script's exit code, so it's a
transparent gate — only the reporting is additive. The wrapped command must
support a `--json` flag; run without --github-report to fall back to the
plain human-readable path with no annotations (useful when iterating locally).

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
    if "field" in f:
        return f"{f.get('field')}: {f.get('kind', '')} {f.get('match', '')!r}"
    if "message" in f:
        return f["message"]
    return json.dumps(f, ensure_ascii=False)


def normalize(payload: dict) -> list[dict]:
    """Best-effort normalization of a checker's --json payload into a flat
    list of finding dicts. Handles the shapes already in use across
    scripts/check_*.py and scripts/translate_audit|metadata/*.py."""
    if "errors" in payload or "warnings" in payload:
        # check_source_strings.py: {"errors": [...], "warnings": [...]}
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


def write_gate_output(name: str, passed: bool) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    key = "".join(c if c.isalnum() else "_" for c in name)
    with open(output_path, "a", encoding="utf-8") as fh:
        fh.write(f"{key}_passed={'true' if passed else 'false'}\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--name", required=True, help="Check name (used in the summary heading and output key).")
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

    findings: list[dict] = []
    try:
        payload = json.loads(proc.stdout)
        findings = normalize(payload)
    except json.JSONDecodeError:
        # Wrapped command doesn't (yet) support --json cleanly — fall back to
        # printing whatever it produced and skip annotations/summary detail.
        sys.stdout.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        write_gate_output(args.name, passed)
        return proc.returncode

    if findings:
        print(f"{args.name}: {len(findings)} finding(s):\n")
        for f in findings:
            print(f"  {_finding_line(f)}")
    else:
        print(f"{args.name}: passed, no findings.")

    emit_annotations(findings)
    write_summary(args.name, passed, findings)
    write_gate_output(args.name, passed)

    return proc.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
