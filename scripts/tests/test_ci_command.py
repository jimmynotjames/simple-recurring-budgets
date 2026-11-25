"""A `/ci ...` PR comment maps to the ci.yml inputs it names, and nothing else starts a run."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

from ci_command import (  # noqa: E402
    EXAMPLE_UI_TEST,
    EXAMPLE_UNIT_TEST,
    TEST_TARGETS,
    USAGE,
    Command,
    parse,
)

UNIT, UI = TEST_TARGETS

EVERYTHING = "lint,secrets,large-files,i18n,tooling,build"


class ParseTests(unittest.TestCase):
    def test_bare_command_runs_the_default_gates_and_build(self) -> None:
        self.assertEqual(parse("/ci"), Command("run", only="", tests="none"))

    def test_single_gate(self) -> None:
        for gate in ("lint", "secrets", "large-files", "i18n", "tooling"):
            with self.subTest(gate=gate):
                self.assertEqual(parse(f"/ci {gate}"), Command("run", only=gate))

    def test_gates_names_all_five_without_build(self) -> None:
        self.assertEqual(parse("/ci gates"), Command("run", only="lint,secrets,large-files,i18n,tooling"))

    def test_build_alone(self) -> None:
        self.assertEqual(parse("/ci build"), Command("run", only="build"))

    def test_unit_runs_only_the_build_job_with_unit_tests(self) -> None:
        self.assertEqual(parse("/ci unit"), Command("run", only="build", tests="unit"))

    def test_ui_runs_only_the_build_job_with_ui_tests(self) -> None:
        self.assertEqual(parse("/ci ui"), Command("run", only="build", tests="ui"))

    def test_all_runs_everything_with_ui_tests(self) -> None:
        self.assertEqual(parse("/ci all"), Command("run", only=EVERYTHING, tests="ui"))

    def test_words_combine_in_job_order(self) -> None:
        self.assertEqual(parse("/ci build i18n lint"), Command("run", only="lint,i18n,build"))
        self.assertEqual(
            parse("/ci gates unit"), Command("run", only=EVERYTHING, tests="unit")
        )

    def test_the_higher_test_level_wins(self) -> None:
        self.assertEqual(parse("/ci ui unit").tests, "ui")
        self.assertEqual(parse("/ci unit ui").tests, "ui")

    def test_case_commas_and_spacing_are_forgiven(self) -> None:
        self.assertEqual(parse("  /CI  Lint,I18N  "), Command("run", only="lint,i18n"))

    def test_only_the_first_line_counts(self) -> None:
        self.assertEqual(parse("/ci lint\nbuild please, and ui"), Command("run", only="lint"))

    def test_help(self) -> None:
        self.assertEqual(parse("/ci help"), Command("help"))
        self.assertEqual(parse("/ci lint help"), Command("help"))

    def test_unknown_words_are_an_error_and_start_nothing(self) -> None:
        self.assertEqual(
            parse("/ci lint tests xyz"), Command("error", error="unknown word(s) `tests xyz`")
        )

    def test_one_class_runs_only_the_build_job_once(self) -> None:
        self.assertEqual(
            parse(f"/ci test {UI}/SomeUITests"),
            Command("run", only="build", test=f"{UI}/SomeUITests"),
        )

    def test_one_test_keeps_its_case_and_repeats(self) -> None:
        self.assertEqual(
            parse(f"/CI Test {UI}/SomeUITests/testEditSomeName X5"),
            Command(
                "run",
                only="build",
                test=f"{UI}/SomeUITests/testEditSomeName",
                iterations=5,
            ),
        )

    def test_a_swift_testing_function_keeps_its_parentheses(self) -> None:
        name = f"{UNIT}/SomeTests/someBehaviour()"
        self.assertEqual(parse(f"/ci test {name}").test, name)

    def test_one_class_combines_with_gates(self) -> None:
        self.assertEqual(
            parse(f"/ci x3 lint test {UNIT}/SomeTests"),
            Command("run", only="lint,build", test=f"{UNIT}/SomeTests", iterations=3),
        )

    def test_a_bad_test_name_starts_nothing(self) -> None:
        for body in (
            "/ci test",
            "/ci test SomeUITests",
            f"/ci test {UI.lower()}/SomeUITests",
            f"/ci test {UI}/A/b/c",
            f"/ci test {UI}/A;rm",
            f"/ci test {UI}x/SomeUITests",
            "/ci test x5",
        ):
            with self.subTest(body=body):
                self.assertEqual(parse(body).action, "error")

    def test_repeats_are_bounded_and_need_a_test(self) -> None:
        name = f"{UI}/SomeUITests"
        self.assertEqual(parse(f"/ci test {name} x10").iterations, 10)
        for body in (f"/ci test {name} x0", f"/ci test {name} x11", "/ci ui x3", "/ci x2"):
            with self.subTest(body=body):
                self.assertEqual(parse(body).action, "error")

    def test_one_class_does_not_combine_with_whole_suites(self) -> None:
        for extra in ("unit", "ui", "all"):
            with self.subTest(extra=extra):
                command = parse(f"/ci {extra} test {UI}/SomeUITests")
                self.assertEqual(command.action, "error")

    def test_only_one_test_per_comment(self) -> None:
        self.assertEqual(
            parse(f"/ci test {UNIT}/A test {UNIT}/B").action, "error"
        )

    def test_the_usage_examples_parse(self) -> None:
        for name in (EXAMPLE_UI_TEST, EXAMPLE_UNIT_TEST):
            with self.subTest(name=name):
                self.assertIn(name, USAGE)
                self.assertEqual(parse(f"/ci test {name}").test, name)

    def test_a_bad_target_names_both_targets(self) -> None:
        error = parse("/ci test Nope/SomeTests").error
        for target in TEST_TARGETS:
            self.assertIn(f"`{target}`", error)

    def test_other_comments_are_ignored(self) -> None:
        for body in ("/cix", "/ci-lint", "please /ci", "", "  \n", "LGTM\n/ci"):
            with self.subTest(body=body):
                self.assertEqual(parse(body).action, "ignore")


if __name__ == "__main__":
    unittest.main()
