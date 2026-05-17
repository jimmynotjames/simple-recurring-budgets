## 1. Domain — split classification

- [x] 1.1 Add `isPausedAtMoment(now:sortedLifecycleEvents:) -> Bool` as a free function alongside `LifecycleClassification.isActive(...)` (or as a private static on `BudgetCalculator`); contract: returns `true` iff the most recent `LifecycleEvent` with `effectiveDate <= now` has `kind == .pause`; consumes `sortedLifecycleEvents` pre-sorted ascending by `(effectiveDate, lastModified)` to match `isActive(...)`.
- [x] 1.2 In `BudgetCalculator.snapshot(...)` recurring branch, compute `uiIsPaused` via the new classifier; preserve the existing `mathIsPaused` (`isCurrentPaused = !isActive(...)`) variable for the `remaining = 0` short-circuit and walker accrual.
- [x] 1.3 Replace the existing `lifecycleState` derivation so that the `.paused` case uses `uiIsPaused`; preserve `.postEnd` and `.preStart` precedence; keep the order: `.postEnd` → `.preStart` → `.paused` → `.active`.
- [x] 1.4 Confirm `BudgetCalculator.specificDatesBranch(...)` is unchanged (the F-2.08 carve-out continues to ignore lifecycle events).
- [x] 1.5 Confirm the carry-over walker (`walkCarryOver(...)`) continues to call `isActive(...)` and is bit-for-bit unchanged.

## 2. Domain tests — verify the two-clock split

- [x] 2.1 Add `BudgetCalculatorMomentGranularPauseTests`: cover (a) mid-period pause flips `lifecycleState` to `.paused` immediately, (b) the same scenario's carry-over walker contribution for the pause-action period is unchanged (still equals `allocation - in-period-expenses`), (c) pause-then-resume in the same period nets to `.active`, (d) pre-start precedence over paused, (e) post-end precedence over paused, (f) empty lifecycle history stays `.active`.
- [x] 2.2 Audit existing `BudgetCalculatorPauseResumeTests` for assertions of the form `lifecycleState == .active` during the pause-action period; update each to either (i) check the math contract via `remaining` / `carryOver` values (which is the stable invariant) or (ii) explicitly assert the new moment-granular value. (Only `snapshot_pauseActionPeriod_isStillActive` was clarified/renamed; other tests use `now` strictly after the pause event and remain correct.)
- [x] 2.3 Add a `LifecycleClassificationMomentGranularTests` (or extend the existing classification tests) to lock in the contract of `isPausedAtMoment(...)` — scan order, tie-breaking, empty input, all-`.resume` history, `effectiveDate == now` boundary.
- [x] 2.4 Update `BudgetLifecycleServiceTests` assertions that previously expected `lifecycleState == .active` during the pause-action period; the service is unchanged but its returned `BudgetLifecycleResult.lifecycleState` will now flip moment-granular. (Audited: existing tests use `now` strictly after the pause event, so moment-granular and period-granular agree — no assertions need updating.)

## 3. Add Expense screen — proactive paused caption

- [x] 3.1 In `AddEditExpenseViewModel`, replace the single `dateOutOfRangeCaption` computed property with a single `pausedCaption` computed property that returns: (a) the violation copy `addEditExpense.date.outOfRange.caption` when the picked date sits inside a paused gap or outside the active union, (b) the proactive copy `addEditExpense.paused.caption.format` (formatted with `cachedPauseEffectiveDate`) when the bound budget is paused and the date is valid, (c) `nil` otherwise. Cache the formatted `pausedSince` date once at init to avoid re-formatting on every body evaluation.
- [x] 3.2 In `AddEditExpenseView.whenCard`, render the `pausedCaption` string (when non-nil) below the `DatePicker` in `.caption`/`.secondary` styling — single line, no stacking.
- [x] 3.3 Confirm `canSave` continues to gate on the violation case only (the proactive paused note is informational and SHALL NOT disable Save by itself); refactor `canSave` to consult a separate `isDateValid` helper rather than the combined `pausedCaption`.
- [x] 3.4 Confirm the date seed for Add mode on a paused budget remains `cachedPauseEffectiveDate` (already implemented); no change needed.

## 4. Add Expense screen tests

- [x] 4.1 Add `AddEditExpensePausedCaptionTests`: cover (a) sheet-open shows the proactive caption when bound budget is paused, (b) editing date within the valid range keeps the proactive caption, (c) picking a date in a paused gap swaps to the violation caption and disables Save, (d) reverting to a valid date restores the proactive caption and re-enables Save, (e) Active-state sheet shows no paused caption, (f) Edit mode on a paused budget shows the proactive caption.
- [x] 4.2 Update `AddEditExpenseDateBoundsTests` if any of its assertions are now redundant with §4.1 — keep the date-range tests, prune duplicate caption-text assertions.

## 5. Detail screen — caption copy tweak

- [x] 5.1 Update the `budgetDetail.action.resume.caption.format` value in `Localizable.xcstrings` from "Paused since %@. Resume to log expenses." to "Paused since %@. Resume to log new expenses." in the en source.
- [x] 5.2 Queue retranslation for all storefront locales via the translation pipeline (`scripts/translate_catalog/` per the project conventions); leave the queue entry committed so the translator pass can run independently. (Translations composed and merged via `scripts/translate_catalog/merge.py` for all 38 locales.)

## 6. Localization — new key for the proactive paused caption

- [x] 6.1 Add new key `addEditExpense.paused.caption.format` to `Localizable.xcstrings` with en source "Paused since %@. You can still add expenses dated before then." and a `comment:` describing the slot ("Proactive caption shown below the When card in Add/Edit Expense when the bound budget is paused; argument is the abbreviated pausedSince date").
- [x] 6.2 Queue translations for all storefront locales. (Translations composed and merged via `scripts/translate_catalog/merge.py` for all 38 locales.)

## 7. Cross-cutting concerns (per docs/main-prd.md §6.8)

- [x] 7.1 Accessibility: confirm VoiceOver order on the Add/Edit Expense sheet picks up the new proactive caption as a static-text element after the When card (no explicit `accessibilityElement` overrides needed — `Text` is already announced by default).
- [x] 7.2 Localized source strings: confirm both string keys (new and updated) use `String(localized: comment:)` with `comment:` set, per project conventions. (Verified: `pausedCaption` getter in `AddEditExpenseViewModel` calls `String(localized: defaultValue: comment:)` for both keys; resume caption already used the pattern.)
- [x] 7.3 Translations queue: confirm both source-string changes are in the translation queue per §6.2. (Covered by 5.2 / 6.2.)
- [x] 7.4 Mixpanel user-action events: no new events; `budget_paused` / `budget_resumed` continue to fire as today. No change required.

## 8. Docs — keep authoritative docs in sync

- [x] 8.1 Update `docs/product-features-planning.md` F-7.06 "Semantics" bullet: replace the period-granular UI claim with the two-clock model — math stays period-granular (no proration); UI flips moment-granular at pause-tap. Add an explicit callout for the same-period-before-pause-moment backdating affordance.
- [x] 8.2 Update `docs/product-features-planning.md` F-2.04 "Date bounds" bullet: clarify that the paused-state upper bound is the pause event's `effectiveDate` (the precise moment) and that same-period-before-pause-moment entries are permitted.
- [x] 8.3 Update `docs/product-features-planning.md` F-2.03 "Allocation-edit semantics" bullet: clarify that "while paused" begins at the pause moment under the moment-granular UI.
- [x] 8.4 Update `docs/tech-design-doc.md` `BudgetCalculator` section: note the split classification — `isActive(...)` for math (period-granular) and `isPausedAtMoment(...)` for UI (moment-granular).
- [x] 8.5 Confirm `docs/main-prd.md` requires no changes (no global constraint or glossary update). Note in tasks.md that this was checked. (Confirmed: §6.7 carry-over and §6.8 cross-cutting concerns are unaffected; glossary needs no update — `lifecycleState`/`paused` terminology unchanged.)

## 9. Build, lint, and verify

- [x] 9.1 Run `make format`.
- [x] 9.2 Run `make lint-fix`.
- [x] 9.3 Run `make build`.
- [x] 9.4 Run `make test`; all tests SHALL pass with zero new lint violations. (379 tests passing, 0 violations.)
- [x] 9.5 Smoke the flow on a fresh simulator: create a daily budget, immediately tap Pause Budget, verify Detail screen flips to "Resume Budget" with the updated caption; open Add Expense via the Budgets-list `+`, verify the proactive paused caption renders; verify the date picker upper bound matches the pause moment; verify a same-period-before-pause-moment entry can be saved. (Confirmed by user 2026-05-16.)
