## ADDED Requirements

### Requirement: Lifecycle write-paths surface save failure to the caller

Each `BudgetLifecycleService` write-path (`pauseBudget`, `resumeBudget`, the allocation-edit write-path, the manual-reset-carry-over write-path, and the reset-budget write-path) SHALL route its `context.save()` call through the shared persistence-save helper (operations `lifecycle_pause`, `lifecycle_resume`, `lifecycle_allocation_edit`, `lifecycle_reset_carry_over`, `lifecycle_reset_budget` respectively) rather than `try? context.save()`. Each method SHALL surface a thrown persistence error to its caller (e.g. by being marked `throws`); the existing eligibility-rejection return value (`Bool`) is preserved, so the method signatures become `throws -> Bool`. Eligibility rejection paths SHALL NOT attempt a save and SHALL NOT throw.

UI callers (Budget detail screen's Pause/Resume actions, Reset Budget, Reset Carry-Over, and any allocation-edit invocation from Add/Edit Budget) SHALL catch a thrown persistence error and present the standard save-error alert (see the `persistence-error-handling` capability) over the presenting screen. The accompanying analytics event for the action (e.g. `budget_paused`, `budget_resumed`, `budget_reset`, `carry_over_reset`) SHALL fire only on a successful save; on a thrown persistence error it SHALL NOT fire.

#### Scenario: Pause save failure surfaces the alert and does not fire budget_paused

- **WHEN** the user taps Pause on an eligible budget and the persistence-save helper throws
- **THEN** `pauseBudget` rethrows the persistence error, the save-error alert is presented over the Budget detail screen, no `budget_paused` analytics event fires, and Retry re-attempts the same pause-and-save

#### Scenario: Resume save failure surfaces the alert and does not fire budget_resumed

- **WHEN** the user taps Resume on an eligible budget and the persistence-save helper throws
- **THEN** `resumeBudget` rethrows the persistence error, the save-error alert is presented, no `budget_resumed` event fires, and Retry re-attempts the same resume-and-save

#### Scenario: Reset Budget save failure surfaces the alert and does not fire budget_reset

- **WHEN** the user confirms Reset Budget and the persistence-save helper throws
- **THEN** the reset-budget method rethrows the persistence error, the save-error alert is presented, no `budget_reset` event fires, and Retry re-attempts the same reset

#### Scenario: Reset Carry-Over save failure surfaces the alert and does not fire carry_over_reset

- **WHEN** the user confirms Reset Carry-Over and the persistence-save helper throws
- **THEN** the manual-reset-carry-over method rethrows the persistence error, the save-error alert is presented, no `carry_over_reset` event fires, and Retry re-attempts the same reset

#### Scenario: Eligibility rejection still returns false without throwing

- **WHEN** `pauseBudget` is called on a `.specificDates` budget, an already-paused budget, or a `.postEnd` budget
- **THEN** the method returns `false` without attempting a save and without throwing a persistence error

---

### Requirement: Background rollover persistence is best-effort

If `BudgetLifecycleService.result(for:)` (or any other read-driven entry point invoked from an eager lifecycle refresh) needs to persist rolled-over state, it SHALL route that save through the shared persistence-save helper (operation `lifecycle_rollover`). The helper logs and fires the `persistence_save_failed` analytics event on failure. The eager-refresh caller SHALL catch and swallow the thrown persistence error without presenting any UI; the rollover is retried by the next natural refresh.

#### Scenario: Background rollover save failure is silent on screen

- **WHEN** an eager lifecycle refresh attempts to persist rolled-over state and the persistence-save helper throws
- **THEN** a `Logger.persistence.error` line and a `persistence_save_failed` event are emitted AND no save-error alert is presented to the user
