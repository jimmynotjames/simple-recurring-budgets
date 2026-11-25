"""Parse a `/ci ...` PR comment into ci.yml's workflow_dispatch inputs.

Run by .github/workflows/ci-command.yml with the comment in $COMMENT_BODY. Writes to
$GITHUB_OUTPUT (or stdout without it):
  action=run|help|error|ignore
  only=<comma list of ci.yml selections, empty for the default gates + build>
  tests=none|unit|ui
  test=<target>/<Suite>[/<test>] to run alone, or empty
  iterations=<how many times to run `test`>
  error=<why the comment started nothing, for the usage reply>
`--usage` prints the usage reply instead.
"""

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass

# --- Repo-specific constants (the rest of this file is identical in checklists and simple-recurring-budgets) ---
TEST_TARGETS = ("simple-recurring-budgetsTests", "simple-recurring-budgetsUITests")  # unit target, UI target
EXAMPLE_UI_TEST = "simple-recurring-budgetsUITests/UserJourneyTests"
EXAMPLE_UNIT_TEST = "simple-recurring-budgetsTests/RecentsAlgorithmTests/dedupIsCaseInsensitive()"
# --- End of repo-specific constants ---

GATES = ("lint", "secrets", "large-files", "i18n")
SELECTIONS = (*GATES, "build")  # ci.yml's `only` vocabulary, in job order
TEST_LEVELS = ("none", "unit", "ui")  # each level includes the ones before it
MAX_ITERATIONS = 10  # bounds one run: each iteration of a UI class takes minutes
# What `make focused-tests` takes: a test target, a class or suite, and optionally one test.
# Swift Testing names a test function with its parentheses.
TEST_ID = re.compile(
    rf"^({'|'.join(map(re.escape, TEST_TARGETS))})/[A-Za-z_]\w*(/[A-Za-z_]\w*(\(\))?)?$", re.ASCII
)
_TARGET_CHOICES = " or ".join(f"`{target}`" for target in TEST_TARGETS)
_ITERATIONS = re.compile(r"^x(\d+)$", re.IGNORECASE)

USAGE = f"""\
**`/ci` usage** — the words after `/ci` on the first line combine:

| Word | Runs |
|---|---|
| *(none)* | all four gates + build, no tests |
| `lint` `secrets` `large-files` `i18n` | that gate |
| `gates` | all four gates |
| `build` | macOS compile check |
| `unit` | build with unit tests |
| `ui` | build with unit then UI tests |
| `all` | all gates + build with unit then UI tests |
| `test <target>/<Class>[/<test>]` | build, then only that class or test |
| `xN` (after `test`) | run that class or test N times, up to 10, e.g. `x5` |
| `help` | this message |

Named tests run only the test job unless gates are named too, e.g. `/ci gates unit`.
`test` takes the name `make focused-tests` takes, case and all, e.g.
`/ci test {EXAMPLE_UI_TEST} x5` or
`/ci test {EXAMPLE_UNIT_TEST}`. It replaces `unit`, `ui`
and `all`, so it can't be combined with them.
Only the repo owner's comments start runs."""

_COMMAND = re.compile(r"^/ci(?:\s+(?P<args>.*))?$", re.IGNORECASE)


@dataclass(frozen=True)
class Command:
    action: str  # run | help | error | ignore
    only: str = ""
    tests: str = "none"
    test: str = ""
    iterations: int = 1
    error: str = ""


def parse(body: str) -> Command:
    first_line = body.strip().splitlines()[0].strip() if body.strip() else ""
    match = _COMMAND.match(first_line)
    if not match:
        return Command("ignore")
    words = [w for w in re.split(r"[\s,]+", match.group("args") or "") if w]
    if not words:
        return Command("run")  # empty `only` is ci.yml's default: gates + build

    selected: set[str] = set()
    tests = "none"
    test = ""
    iterations: int | None = None
    unknown: list[str] = []
    wants_help = False
    words_left = iter(words)
    for original in words_left:
        word = original.lower()  # keywords are case-insensitive; the test name is not
        iteration_match = _ITERATIONS.match(word)
        if word == "help":
            wants_help = True
        elif word in SELECTIONS:
            selected.add(word)
        elif word == "gates":
            selected.update(GATES)
        elif word in ("unit", "ui"):
            selected.add("build")
            tests = max(tests, word, key=TEST_LEVELS.index)
        elif word == "all":
            selected.update(SELECTIONS)
            tests = "ui"
        elif word == "test":
            name = next(words_left, "")
            if test:
                return Command("error", error="`test` can name only one class or test")
            if not TEST_ID.match(name):
                return Command(
                    "error",
                    error=f"`test` needs `<target>/<Class>[/<test>]` with target {_TARGET_CHOICES}, "
                    f"not `{name or '(nothing)'}`",
                )
            test = name
            selected.add("build")
        elif iteration_match:
            iterations = int(iteration_match.group(1))
        else:
            unknown.append(original)

    if unknown:
        return Command("error", error=f"unknown word(s) `{' '.join(unknown)}`")
    if wants_help:
        return Command("help")
    if test and tests != "none":
        return Command("error", error="`test` can't be combined with `unit`, `ui` or `all`")
    if iterations is not None and not test:
        return Command("error", error="`xN` repeats a `test`, so it needs one")
    if iterations is not None and not 1 <= iterations <= MAX_ITERATIONS:
        return Command("error", error=f"`x{iterations}` is outside 1-{MAX_ITERATIONS}")
    return Command(
        "run",
        only=",".join(s for s in SELECTIONS if s in selected),
        tests=tests,
        test=test,
        iterations=iterations or 1,
    )


def main(argv: list[str]) -> int:
    if argv[1:] == ["--usage"]:
        print(USAGE)
        return 0
    command = parse(os.environ.get("COMMENT_BODY", ""))
    lines = [f"{key}={getattr(command, key)}" for key in ("action", "only", "tests", "test", "iterations", "error")]
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    else:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
