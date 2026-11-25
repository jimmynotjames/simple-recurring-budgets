# Flaky tests

Every flaky sighting, UI and unit tests alike, so the flakes can be fixed together once there's
enough data. What counts as flaky and when to log it: AGENTS.md §"Reading a test result".

- **Append only.** Add one row per sighting, even for a test that already has one. A second sighting
  of the same test is the signal worth acting on. A test's rows leave only with the change that
  fixes it.
- **Committing a row:** a sighting on a feature branch goes in that branch's PR. A sighting on `main`
  stays uncommitted and rides along with the next PR.
- Rows describe what was seen, not how the code got there: no history wording (AGENTS.md §"Comment
  and prose style").

| Date | Test | File:line | Failure | Run (suite, branch@sha, bundle) | Isolated rerun | Hunch |
|---|---|---|---|---|---|---|
| 2026-11-25 | `UserJourneyTests/testReorderBudgets` | `UserJourneyTests.swift:239` | `XCTAssertLessThan` "Charlie should render above Alpha after the drag": the drag didn't reorder; failed 1 of 10 | `/ci test … x10`, animations off, `claude/ci-spot-check@484244a`, [xcresults-focused-tests](https://github.com/jimmynotjames/simple-recurring-budgets/actions/runs/45629330307/artifacts/15032133850) | Same x10 with animations on: 10 of 10 | The drag sometimes doesn't take; animations aren't the cause (next row) |
| 2026-11-25 | `UserJourneyTests/testReorderBudgets` | `UserJourneyTests.swift:243` | Same assertion; failed both the run and its retry | `ui-tests (user-journey)`, animations on for this test only, `claude/reorder-keeps-animations@4bb3277`, [xcresults-ui-tests-user-journey](https://github.com/jimmynotjames/simple-recurring-budgets/actions/runs/45653655881/artifacts/15046842462) | See the row above: 10 of 10 isolated, animations on | Fails more in a full shard than isolated, with animations on or off |
| 2026-11-25 | `UserJourneyTests/testAddExpenseFromBudgetRow` | `UITestHelpers.swift:92` | `XCTAssertTrue` on the Expense amount field's `waitForExistence(timeout: 2)`; passed on retry | `ui-tests (user-journey)`, `claude/reorder-keeps-animations@4bb3277`, [xcresults-ui-tests-user-journey](https://github.com/jimmynotjames/simple-recurring-budgets/actions/runs/45653655881/artifacts/15046842462) | Not rerun | The 2 s wait is tight for the sheet on a loaded CI runner |
