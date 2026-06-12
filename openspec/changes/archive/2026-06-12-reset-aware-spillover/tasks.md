# Tasks — reset-aware-spillover

## 1. Core implementation

- [x] 1.1 In `BudgetCalculator.recurringBranch`, compute a reset-aware `spilloverRemaining` (expense lower bound `max(effectivePeriodStart, lastResetDate ?? .distantPast)`, full allocation, preserving the `isCurrentPaused → 0` short-circuit) and pass it to `currentPeriodSpillover` instead of `remaining`; leave `remaining` itself untouched.
- [x] 1.2 Suppress spillover entirely when `budget.lastResetDate >= effectiveEndExclusive` (post-end reset).
- [x] 1.3 Update doc comments in `BudgetCalculator.swift` / `CurrentPeriodSpillover.swift` to state the reset-interaction rule and the live/close-time equivalence.

## 2. Tests

- [x] 2.1 Mid-period Reset Carry-Over with current deficit → carry-over 0, remaining unchanged (#242 scenario).
- [x] 2.2 Post-reset overspend spills again (input = allocation − post-reset expenses).
- [x] 2.3 Live spillover equals walker close-time contribution for the reset period (advance `now` past the period boundary and compare).
- [x] 2.4 Post-end Reset Carry-Over zeroes carry-over permanently (#241 scenario).
- [x] 2.5 Post-end Reset Budget (expenses deleted) yields carry-over 0, not the final allocation (#241 scenario).
- [x] 2.6 Reset during the final period of a budget that later ends → postEnd spillover folds post-reset expenses only.
- [x] 2.7 No-reset behavior unchanged: existing suites pass without modification (except any that pinned the buggy behavior — update those deliberately and note it). Result: full suite green with zero existing-test edits.

## 3. Docs & spec sync

- [x] 3.1 Update `docs/budget-calculations-rewrite-algorithm.md` §A.5.6 (spillover rule), §A.6.4 (Reset Carry-Over), §A.6.5 (Reset Budget) with the reset-interaction rule.
- [x] 3.2 Confirm `docs/main-prd.md`, `docs/product-features-planning.md`, `docs/tech-design-doc.md` need no edits (no F-x.xx or architecture change); note in PR if so.

## 4. Gate

- [x] 4.1 Run `make format` → `make lint-fix` → `make build` → `make test` and fix anything surfaced. Result: all four steps green, nothing surfaced.
