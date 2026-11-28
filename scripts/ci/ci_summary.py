#!/usr/bin/env python3
"""Sum up a CI run: the job summary page, and a comment on the PR the run belongs to.

Run by ci.yml's `summary` job (needs every other job, `if: always()`). Python 3 stdlib plus the
`gh` CLI, authenticated by GH_TOKEN. The token needs actions:read, checks:read and
pull-requests:write.

Subcommands:
  find-pr   Print the run's PR number, or nothing when it has none.
  post      Render the summary, append it to $GITHUB_STEP_SUMMARY when set, and post it on the PR.
            --reports DIR    where the `test-report-*` artifacts were downloaded; every
                             `test-report-*.json` under it is read (missing dir: none)
            --tally FILE     a focused-tests tally line; a missing or empty file is ignored
            --flaky-log PATH the repo's flaky-test log, named in "Passed only on retry"
            --pr N           post on this PR instead of resolving one

Read from the environment: GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_SERVER_URL,
GITHUB_EVENT_NAME, GITHUB_SHA, GITHUB_REF_NAME, GITHUB_HEAD_REF, GITHUB_JOB, GITHUB_EVENT_PATH
(the PR number and head, the dispatch inputs and the pushed commit's subject come from it),
GITHUB_STEP_SUMMARY, plus:
  CI_CODE       `changes.code`; "false" adds the docs-only note (on a push: the already-tested note)
  CI_COMMAND    the `/ci` command words, if the run came from a /ci comment
  CI_ONLY, CI_TESTS, CI_TEST, CI_ITERATIONS, CI_PR   override the dispatch inputs
  CI_SELF_JOB   the summary job's name, left out of the table (default: GITHUB_JOB)

The PR: pull_request uses its own; workflow_dispatch uses inputs.pr, else the open PR whose head is
the branch; push uses the PR the commit belongs to, else a trailing `(#NNN)` in its subject. No PR
means the step summary only. A pull_request run keeps one comment starting with `<!-- ci-summary -->`
and edits it; any other run posts a new comment starting with `<!-- ci-summary:event -->`. Posting
is best-effort: a failure prints `::warning::` and the script still exits 0.

Each test job uploads `test-report-<job>.json`, written by
`scripts/list_test_failures.py --json PATH --rc N --job NAME <bundle>`:
  {"job": str, "rc": int|null, "failures": [{"test", "location", "text"}],
   "retry_only_passes": [{"test", "location", "text"}], "counts": {"total": int, "<result>": int}}
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Callable

STICKY = "<!-- ci-summary -->"
EVENT_MARK = "<!-- ci-summary:event -->"
CAP = 60_000
TOP_ANNOTATIONS = 20
LINE_MAX = 400
ICONS = {"success": "✅", "failure": "❌", "timed_out": "⏱️", "cancelled": "🚫", "skipped": "⏭️"}
FAILED = {"failure", "timed_out", "startup_failure"}
INPUTS = ("only", "tests", "test", "iterations", "pr")

Gh = Callable[..., str]


class GhError(Exception):
    pass


def run_gh(args: list[str], stdin: str | None = None) -> str:
    result = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise GhError(f"gh {' '.join(args[:2])}: {result.stderr.strip()[:300]}")
    return result.stdout


def _json_lines(text: str) -> list[dict]:
    """`gh api --paginate --jq '.x[]'` prints one compact JSON value per line."""
    return [json.loads(line) for line in text.splitlines() if line.strip()]


# --- Context and PR resolution -------------------------------------------------------------------

def load_context(env: dict, payload: dict) -> dict:
    pr = payload.get("pull_request") or {}
    head = pr.get("head") or {}
    inputs = payload.get("inputs") or {}
    message = (payload.get("head_commit") or {}).get("message") or ""
    return {
        "repo": env.get("GITHUB_REPOSITORY", ""),
        "run_id": env.get("GITHUB_RUN_ID", ""),
        "server_url": env.get("GITHUB_SERVER_URL", "https://github.com"),
        "event": env.get("GITHUB_EVENT_NAME", ""),
        "branch": head.get("ref") or env.get("GITHUB_HEAD_REF") or env.get("GITHUB_REF_NAME", ""),
        "sha": head.get("sha") or env.get("GITHUB_SHA", ""),
        "event_pr": str(pr.get("number") or ""),
        "inputs": {k: str(env.get(f"CI_{k.upper()}") or inputs.get(k) or "").strip() for k in INPUTS},
        "command": re.sub(r"^/ci\b", "", env.get("CI_COMMAND", "").strip()).strip(),
        "code": env.get("CI_CODE", "").strip().lower(),
        "subject": message.splitlines()[0] if message else "",
        "self_job": env.get("CI_SELF_JOB") or env.get("GITHUB_JOB") or "summary",
    }


def _number(text: str) -> str:
    text = text.strip()
    return text if text.isdigit() else ""


def resolve_pr(ctx: dict, gh: Gh) -> str:
    """The PR number this run reports to, or "" for none."""
    event, repo = ctx["event"], ctx["repo"]
    if event == "pull_request":
        return _number(ctx["event_pr"])
    if event == "workflow_dispatch":
        if ctx["inputs"]["pr"]:
            return _number(ctx["inputs"]["pr"])
        if not ctx["branch"]:
            return ""
        try:
            return _number(gh(["pr", "list", "--repo", repo, "--head", ctx["branch"], "--state",
                               "open", "--json", "number", "--jq", ".[0].number // empty"]))
        except GhError as error:
            print(f"Could not look up the branch's PR: {error}", file=sys.stderr)
            return ""
    if event == "push":
        try:
            found = _number(gh(["api", f"repos/{repo}/commits/{ctx['sha']}/pulls",
                                "--jq", ".[0].number // empty"]))
            if found:
                return found
        except GhError as error:
            print(f"Could not look up the commit's PR: {error}", file=sys.stderr)
        match = re.search(r"\(#(\d+)\)\s*$", ctx["subject"])
        return match.group(1) if match else ""
    return ""


def selection(inputs: dict) -> str:
    tests = (f"test=`{inputs['test']}` x{inputs['iterations'] or '1'}" if inputs["test"]
             else f"tests={inputs['tests'] or 'none'}")
    return f"{inputs['only'] or 'gates+build'}, {tests}"


def describe_trigger(ctx: dict) -> str:
    event = ctx["event"]
    if event == "pull_request":
        return "PR push"
    if event == "push":
        return "push to main after merge" if ctx["branch"] == "main" else f"push to `{ctx['branch']}`"
    if event == "workflow_dispatch":
        if ctx["command"]:
            return f"`/ci {ctx['command']}`"
        kind = "`/ci`" if ctx["inputs"]["pr"] else "manual dispatch"
        return f"{kind} ({selection(ctx['inputs'])})"
    return event or "unknown event"


# --- Data ----------------------------------------------------------------------------------------

def _seconds(start: str | None, end: str | None) -> float | None:
    if not start or not end:
        return None
    parse = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))  # noqa: E731
    return max(0.0, (parse(end) - parse(start)).total_seconds())


# A skipped matrix job never expands its matrix, so GitHub names it `ui-tests (${{ matrix.shard }})`.
_UNEXPANDED_MATRIX = re.compile(r"\s*\([^()]*\$\{\{[^()]*\}\}[^()]*\)")


def job_name(raw_name: str | None) -> str:
    return _UNEXPANDED_MATRIX.sub("", raw_name or "").strip() or "?"


def job_rows(raw: list[dict], self_job: str) -> list[dict]:
    rows = []
    for job in raw:
        if job.get("name") == self_job:
            continue
        rows.append({
            "id": job.get("id"), "name": job_name(job.get("name")),
            "conclusion": job.get("conclusion") or job.get("status") or "?",
            "started": job.get("started_at"), "completed": job.get("completed_at"),
            "seconds": _seconds(job.get("started_at"), job.get("completed_at")),
        })
    return rows


def wall_seconds(rows: list[dict]) -> float | None:
    starts = [r["started"] for r in rows if r["started"] and r["completed"]]
    ends = [r["completed"] for r in rows if r["started"] and r["completed"]]
    return _seconds(min(starts), max(ends)) if starts else None


def pick_annotations(found: list[dict]) -> list[dict]:
    """Failures before warnings, in job order, at most TOP_ANNOTATIONS."""
    kept = [a for a in found if a.get("level") in ("failure", "warning")]
    kept.sort(key=lambda a: a["level"] != "failure")
    return kept[:TOP_ANNOTATIONS]


def load_reports(directory: str | None) -> list[dict]:
    if not directory or not Path(directory).is_dir():
        return []
    reports = []
    for path in sorted(Path(directory).rglob("test-report-*.json")):
        try:
            report = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        report.setdefault("job", path.stem.removeprefix("test-report-"))
        reports.append(report)
    return reports


def collect(ctx: dict, gh: Gh, reports_dir: str | None, tally_path: str | None) -> dict:
    """Everything render() needs; each gh read that fails leaves its part empty."""
    repo, run = ctx["repo"], ctx["run_id"]

    def read(what: str, args: list[str]) -> list[dict]:
        try:
            return _json_lines(gh(["api", "--paginate", *args]))
        except (GhError, ValueError) as error:
            print(f"::warning::CI summary could not read {what}: {error}")
            return []

    jobs = job_rows(read("the jobs", [f"repos/{repo}/actions/runs/{run}/jobs", "--jq", ".jobs[]"]),
                    ctx["self_job"])
    annotations = []
    for job in jobs:
        if job["conclusion"] in ("skipped", "?") or job["id"] is None:
            continue
        for a in read(f"{job['name']}'s annotations",
                      [f"repos/{repo}/check-runs/{job['id']}/annotations", "--jq", ".[]"]):
            annotations.append({"job": job["name"], "level": a.get("annotation_level"),
                                "path": a.get("path"), "line": a.get("start_line"),
                                "title": a.get("title") or "", "message": a.get("message") or ""})
    run_url = f"{ctx['server_url']}/{repo}/actions/runs/{run}"
    bundles = [{"name": a["name"], "url": f"{run_url}/artifacts/{a['id']}"}
               for a in read("the artifacts", [f"repos/{repo}/actions/runs/{run}/artifacts",
                                               "--jq", ".artifacts[]"])
               if str(a.get("name", "")).startswith("xcresults-")]
    tally = ""
    if tally_path and Path(tally_path).is_file():
        tally = Path(tally_path).read_text().strip()
    return {
        "trigger": describe_trigger(ctx), "branch": ctx["branch"], "sha": ctx["sha"],
        "run_url": run_url, "run_id": run, "code": ctx["code"], "event": ctx["event"], "jobs": jobs,
        "wall_seconds": wall_seconds(jobs), "reports": load_reports(reports_dir),
        "annotations": pick_annotations(annotations), "tally": tally, "bundles": bundles,
        "marker": STICKY if ctx["event"] == "pull_request" else EVENT_MARK,
    }


# --- Rendering (pure) ----------------------------------------------------------------------------

def fmt_duration(seconds: float | None) -> str:
    if seconds is None:
        return "—"
    s = int(round(seconds))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m {s % 60:02d}s"
    return f"{s // 3600}h {s % 3600 // 60:02d}m"


def _one_line(text: str) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= LINE_MAX else text[: LINE_MAX - 1] + "…"


def verdict(data: dict) -> tuple[str, str]:
    conclusions = {j["conclusion"] for j in data["jobs"]}
    if conclusions & FAILED or any(r.get("failures") for r in data["reports"]):
        return "❌", "failed"
    if "cancelled" in conclusions:
        return "🚫", "cancelled"
    if not data["jobs"]:
        return "⚪", "finished (job list unavailable)"
    return "✅", "passed"


def _test_lines(report_entries: list[tuple[str, dict]]) -> list[str]:
    return [f"- **{job}** `{f.get('test', '?')}` at `{f.get('location', '?')}`: "
            f"{_one_line(f.get('text', ''))}" for job, f in report_entries]


def render(data: dict) -> str:
    icon, word = verdict(data)
    head = [
        data["marker"],
        f"### {icon} CI {word}",
        "",
        f"{data['trigger']} · `{data['branch']}@{data['sha'][:7]}` · "
        f"[run {data['run_id']}]({data['run_url']}) · wall-clock {fmt_duration(data['wall_seconds'])}",
        "",
    ]
    if data["code"] == "false" and data.get("event") == "push":
        head += ["Already tested: this commit's code passed CI on its PR, so the build and tests "
                 "were skipped.", ""]
    elif data["code"] == "false":
        head += ["Docs-only change: the build and tests were skipped.", ""]

    sections: list[tuple[str, list[str]]] = []
    if data["jobs"]:
        table = ["| | Job | Result | Time |", "|---|---|---|---|"]
        table += [f"| {ICONS.get(j['conclusion'], '⚪')} | `{j['name'].replace('|', '/')}` | "
                  f"{j['conclusion']} | {fmt_duration(j['seconds'])} |" for j in data["jobs"]]
        sections.append(("Jobs", table))
    counted = [r for r in data["reports"] if r.get("counts")]
    if counted:
        sections.append(("Tests run", [
            f"- **{r['job']}**: " + ", ".join(f"{n} {k}" for k, n in r["counts"].items())
            for r in counted]))
    failures = [(r["job"], f) for r in data["reports"] for f in r.get("failures") or []]
    if failures:
        sections.append(("Failed tests", _test_lines(failures)))
    retried = [(r["job"], f) for r in data["reports"] for f in r.get("retry_only_passes") or []]
    if retried:
        log = f" (`{data['flaky_log']}`)" if data.get("flaky_log") else ""
        sections.append(("Passed only on retry", [
            f"These failed, then passed on retry: log each one in the flaky-test log{log}.", "",
            *_test_lines(retried)]))
    if data["annotations"]:
        sections.append((f"Annotations (top {TOP_ANNOTATIONS})", [
            f"- {'❌' if a['level'] == 'failure' else '⚠️'} **{a['job']}** "
            + (f"`{a['path']}:{a['line']}` " if a.get("path") and a["path"] != ".github" else "")
            + _one_line(f"{a['title']}: {a['message']}" if a["title"] else a["message"])
            for a in data["annotations"]]))
    if data["tally"]:
        sections.append(("Focused tally", [data["tally"]]))
    if data["bundles"]:
        sections.append(("Result bundles", [f"- [{b['name']}]({b['url']})" for b in data["bundles"]]))

    # Sections fill in order; the first that overflows is cut with a note, and later ones become a
    # note each. The reserve pays for those notes.
    out = "\n".join(head) + "\n"
    remaining = CAP - len(out) - 1_500
    note = f"the summary is capped at {CAP:,} characters; see the [run]({data['run_url']})._"
    for title, lines in sections:
        block = f"#### {title}\n\n"
        if remaining <= len(block):
            out += f"{block}_Not shown: {note}\n\n"
            continue
        for index, line in enumerate(lines):
            if len(block) + len(line) + 1 > remaining:
                block += f"\n_{len(lines) - index} more lines not shown: {note}\n"
                remaining = 0
                break
            block += line + "\n"
        else:
            remaining -= len(block) + 1
        out += block + "\n"
    return out.rstrip() + "\n"


# --- Posting -------------------------------------------------------------------------------------

def post_comment(repo: str, pr: str, body: str, sticky: bool, gh: Gh) -> str:
    payload = json.dumps({"body": body})
    if sticky:
        ids = gh(["api", "--paginate", f"repos/{repo}/issues/{pr}/comments", "--jq",
                  f'.[] | select(.user.type == "Bot" and (.body | startswith("{STICKY}"))) | .id']).split()
        if ids:
            gh(["api", "-X", "PATCH", f"repos/{repo}/issues/comments/{ids[0]}", "--input", "-"], payload)
            return "updated"
    gh(["api", "-X", "POST", f"repos/{repo}/issues/{pr}/comments", "--input", "-"], payload)
    return "posted"


def main(argv: list[str] | None = None, env: dict | None = None, gh: Gh = run_gh) -> int:
    env = dict(os.environ) if env is None else env
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("find-pr")
    post = sub.add_parser("post")
    post.add_argument("--reports")
    post.add_argument("--tally")
    post.add_argument("--flaky-log")
    post.add_argument("--pr", default="")
    args = parser.parse_args(argv)

    payload: dict = {}
    if env.get("GITHUB_EVENT_PATH") and Path(env["GITHUB_EVENT_PATH"]).is_file():
        payload = json.loads(Path(env["GITHUB_EVENT_PATH"]).read_text() or "{}")
    ctx = load_context(env, payload)
    if args.command == "find-pr":
        print(resolve_pr(ctx, gh))
        return 0

    data = collect(ctx, gh, args.reports, args.tally)
    data["flaky_log"] = args.flaky_log
    body = render(data)
    if env.get("GITHUB_STEP_SUMMARY"):
        with open(env["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write(body)
    pr = _number(args.pr) or resolve_pr(ctx, gh)
    if not pr:
        print("No PR for this run: wrote the step summary only.")
        return 0
    try:
        done = post_comment(ctx["repo"], pr, body, ctx["event"] == "pull_request", gh)
        print(f"CI summary {done} on PR #{pr}.")
    except GhError as error:
        print(f"::warning::CI summary not posted on PR #{pr}: {error}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
