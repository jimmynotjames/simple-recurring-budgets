## Context

The biweekly start-date UX (explanatory note, Schedule auto-expand, Save-time re-anchor confirmation, and the clarified period-lock caption) was designed and implemented in a workshop session and shipped on the `biweekly-startdate-ux` branch (PR #251), including the 49-locale translations. This change exists to **formalize** that shipped behavior: lock it into the `add-edit-budget-screen` spec, backfill the test coverage that was deliberately deferred, and align `docs/product-features-planning.md`. No UI or copy is (re)designed here — those decisions are final and in production.

The motivating fact: biweekly is the only recurring period whose 14-day grid is anchored to the budget's own `startDate` (`BudgetCalculator.recurringBranch` sets `biweeklyAnchor = effectiveStartDate`; `PeriodCalculator.periodStart`'s `.biweekly` branch derives phase from it). Daily resets daily, weekly grids on the global `AppSettings.weekStartDay`, monthly on the calendar month — none anchor on the start day. So only biweekly needs the note, the auto-expand, and the re-anchor confirmation.

## Goals / Non-Goals

**Goals:**
- Capture the shipped biweekly UX as testable spec requirements.
- Backfill unit + UI test coverage (the deferred item from the implementation plan).
- Fix the F-2.03 doc drift (period-lock caption copy) and add F-2.03 acceptance criteria for the new biweekly UX.

**Non-Goals:**
- Changing any UI, copy, or behavior — all are shipped and final.
- Any calculator/period-math change — the math is unchanged (the calculators already re-derive the anchor from `startDate`).
- New analytics — `budget_edited` already carries `start_date_changed`.
- UI test screen-object work is **in scope** here (it was the deferred tail of the original plan).

## Decisions

These were resolved during the workshop and are recorded here for provenance; they are now constraints, not open choices.

- **Re-anchor confirmation fires at Save, not at date-pick.** The Settings "Week Starts On" picker confirms at change because Settings has no Save step; this sheet does, and already owns a Save-time confirmation (the orphan warning). Save-time fires once and composes cleanly with the orphan path. Alternative (intercept the date picker like Settings) was rejected: it double-alerts with the orphan warning and re-fires on every re-pick.
- **One alert in the overlap, orphan sentence folded in.** When a biweekly start-date edit also strands expenses, the re-anchor alert takes precedence and appends the orphan sentence to its body (`biweeklyReanchorMessage`), rather than stacking two alerts. The orphan data-consequence is preserved; the warnings never queue.
- **Auto-expand reuses the existing Schedule disclosure; it does not clone the Specific Dates `datesCard`.** Flipping `isScheduleExpanded` for biweekly is one line and inherits the disclosure's "end date is optional" framing (the end chip reads "No end date"). Cloning the mandatory-dates Specific Dates card would have implied both dates are required — the exact End Date confusion we wanted to avoid.
- **Gate lives on the ViewModel as `isBiweeklyStartDateEdited`.** Mirrors `orphanedExpenseCount` (pure, testable, draft-vs-persisted), so the Save-gate logic is unit-testable without the View.
- **Copy: "Period type can't be changed…".** The old caption ("This can't be changed…") read as if it governed the whole section, but dates remain editable in edit mode for every period type — only the period *type* is locked. The VoiceOver hint was aligned to match.

## Risks / Trade-offs

- **Retroactive carry-over recompute is now more discoverable.** [Surfacing the start date for biweekly means more users will edit it, and moving the anchor re-slices all past periods and the carry-over figure.] → This is existing, mathematically-consistent behavior; the new confirmation explicitly warns about it ("recalculate past periods"). No mitigation beyond the warning is warranted.
- **`biweeklyReanchorMessage` is a private `View` computed property.** [Its base-vs-folded composition can't be reached by a ViewModel unit test.] → Unit-test the testable gate (`isBiweeklyStartDateEdited`) and the orphan count (`orphanedExpenseCount`) that drive it; assert the composed alert behavior at the UI-test layer (journey) where the alert is observable. The composition logic itself is a trivial string concat behind an `orphanedExpenseCount > 0` guard.
- **UI tests are slow and occasionally simulator-flaky.** → Keep the new journey minimal and update `AddBudgetScreen` proactively (per PRD §6.8.5) so the suite doesn't loop on stale element queries.

## Migration Plan

Not applicable — the behavior is already deployed. Apply work is additive: tests + docs. The four-step gate (`make format → make lint-fix → make build → make test`) runs at apply; translations are already merged and green (`check_translations.py`), so no translation run is required unless apply adds further user-facing strings (it should not).

## Open Questions

None. (Whether to keep the biweekly UX on the same PR vs split is already settled — it's one PR, #251; this OpenSpec change rides the same branch.)
