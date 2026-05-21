## 1. View-layer foundation

- [x] 1.1 Create `simple-recurring-budgets/Views/BudgetInactiveReason.swift` with the enum (`.preStart(startDate:)`, `.paused(since:)`, `.postEnd(endDate:)`) and the `static func from(lifecycle:budget:) -> BudgetInactiveReason?` helper per design §1. Include defensive `guard let` for the date payloads with an `assertionFailure` on the unexpected branch.
- [x] 1.2 Add unit tests for `BudgetInactiveReason.from(...)` covering all four `BudgetLifecycleState` cases plus the defensive nil-date branches (Swift Testing framework, per `docs/tech-design-doc.md`).

## 2. RemainingBar generalization

- [x] 2.1 Update `simple-recurring-budgets/Views/RemainingBar.swift` so that when `dimmed == true`, the filled capsule renders at **full width** in `.secondary` (drop the `geo.size.width * remainingFraction` for that branch). Leave the active path unchanged.
- [x] 2.2 Add a preview showing the dimmed full-width render alongside the active fraction-driven render so reviewers can compare side-by-side.

## 3. InactiveStatusChip

- [x] 3.1 Rename `simple-recurring-budgets/Views/PausedChip.swift` to `simple-recurring-budgets/Views/InactiveStatusChip.swift`. Replace the `pausedSince: Date` initializer with `reason: BudgetInactiveReason`. Dispatch on the case for icon (`calendar.badge.clock` / `pause.circle.fill` / `checkmark.circle`) and label key (`chip.inactive.preStart.label.format` / `chip.paused.label.format` / `chip.inactive.postEnd.label.format`). Preserve capsule styling, increased-contrast handling, Dynamic-Type-scaled padding.
- [x] 3.2 Add per-variant accessibility labels: `chip.inactive.preStart.accessibilityLabel.format`, `chip.paused.accessibilityLabel.format` (reused), `chip.inactive.postEnd.accessibilityLabel.format`.
- [x] 3.3 Add SwiftUI previews for all three variants in light and dark mode.

## 4. StatusChipRow signature

- [x] 4.1 In `simple-recurring-budgets/Views/StatusChipRow.swift`, replace `isPaused: Bool` + `pausedSince: Date?` with `inactiveReason: BudgetInactiveReason?`. Render `InactiveStatusChip(reason:)` in the first chip slot whenever `inactiveReason != nil`. Update `showsRow` to `inactiveReason != nil || isCarryOverEnabled`. Pass `dimmed: inactiveReason != nil` into `CarryOverChip`.
- [x] 4.2 Update the `where Trailing == EmptyView` convenience initializer to match the new parameter shape.
- [x] 4.3 Update existing previews and add new ones covering the preStart, paused, and postEnd variants (with and without carry-over chip).

## 5. BudgetRemainingSummary signature

- [x] 5.1 In `simple-recurring-budgets/Views/BudgetRemainingSummary.swift`, replace `isPaused: Bool` with `inactiveReason: BudgetInactiveReason?`. Add a `displayedAmount` computed property that returns `allocation` for `.preStart`/`.postEnd` and `remaining` otherwise. Drive `amountText` from `displayedAmount`. Make `isOverBudget` evaluate against `displayedAmount` (so allocation-mode never reads as over budget). Pass `dimmed: inactiveReason != nil` to `RemainingBar`.
- [x] 5.2 Extend `BudgetRemainingSummary.accessibilityLabel(...)` to take `inactiveReason: BudgetInactiveReason?` and dispatch to the new per-reason keys (preStart / postEnd) while keeping the existing paused / active / over-budget / specificDates keys intact.
- [x] 5.3 Update previews to cover all three inactive variants (preStart, paused, postEnd) in addition to the existing active / over-budget / paused cases.

## 6. BudgetsView.BudgetRowView wiring

- [x] 6.1 In `simple-recurring-budgets/Views/BudgetsView.swift`, remove the `isPaused` derivation on `BudgetRowView`. Introduce a `inactiveReason: BudgetInactiveReason?` computed property derived via `BudgetInactiveReason.from(lifecycle:budget:)`.
- [x] 6.2 Pass `inactiveReason` into both `BudgetRemainingSummary(...)` and `StatusChipRow(...)`. Update the `accessibilityLabel(...)` call site to pass `inactiveReason` as well.
- [x] 6.3 Verify in previews that the existing "xxxLarge" / "Empty state" / "Dark Mode" previews still render correctly, and add a "Pre-start" + "Post-end" preview to the existing matrix.

## 7. BudgetDetailView wiring

- [x] 7.1 In `simple-recurring-budgets/Views/BudgetDetailView.swift`, remove the `isPaused` derivation (and keep `isPostEnd` only because it gates `showPauseResumeItem`). Introduce a `inactiveReason: BudgetInactiveReason?` computed property.
- [x] 7.2 In `headerRow`, pass `inactiveReason` into both `BudgetRemainingSummary(...)` and `StatusChipRow(...)`. Update the `accessibilityLabel(...)` call site.
- [x] 7.3 Confirm the primary action slot logic (`if isPaused { Resume } else { AddExpense }`) is unchanged — it continues to read `isPaused` from the lifecycle state directly, since the slot's behavior is per the existing budget-detail-screen spec (this change explicitly does NOT modify the primary-slot requirement). Add a code comment if the boolean derivation is moved.
- [x] 7.4 Add SwiftUI previews for pre-start, post-end, and Specific-Dates-out-of-window scenarios in `BudgetDetailPreview` using `DebugData` (add new factories under `simple-recurring-budgets/PreviewSupport/DebugData.swift` if missing).

## 8. Localization (cross-cutting per docs/main-prd.md §6.8)

- [x] 8.1 Add new keys to `simple-recurring-budgets/Localizable.xcstrings` with `comment:` strings written for translators (all in the same edit so `translate-new-strings` picks them up in one pass):
  - `chip.inactive.preStart.label.format`
  - `chip.inactive.preStart.accessibilityLabel.format`
  - `chip.inactive.postEnd.label.format`
  - `chip.inactive.postEnd.accessibilityLabel.format`
  - `budget.summary.accessibilityLabel.preStart`
  - `budget.summary.accessibilityLabel.postEnd`
- [x] 8.2 Run `scripts/translate_catalog/` via the `translate-new-strings` skill to translate the new keys into all 38 storefront locales. Verify `check_translations.py` reports no outstanding issues.
- [x] 8.3 Confirm no existing keys were removed (paused keys remain in place).

## 9. Tests

- [x] 9.1 Add Swift Testing tests for `BudgetRemainingSummary.accessibilityLabel(...)` covering all six paths (active / over-budget / paused / preStart / postEnd / specificDates) including the name-prefix vs name-omitted variants.
- [x] 9.2 Add Swift Testing tests for `BudgetInactiveReason.from(lifecycle:budget:)` covering all four lifecycle states plus the defensive nil-date fallthrough.
- [x] 9.3 Add a snapshot-style visual test (or an explicit preview-comparison preview group) showing the active row vs. each inactive variant for both `BudgetRowView` and `BudgetDetailView.headerRow`. (If the project doesn't yet have a snapshot harness, document the manual comparison in the PR description per `docs/tech-design-doc.md` testing guidance.)

## 10. Doc alignment (per AGENTS.md > Doc maintenance protocol)

- [x] 10.1 Update `docs/product-features-planning.md` F-2.01 ("Budgets screen") to describe a single unified "Inactive presentation" rule rather than the current paused-only description; reference `BudgetInactiveReason` as the view-layer driver.
- [x] 10.2 Update `docs/product-features-planning.md` F-2.02 ("Budget detail screen") similarly — the header description should call out the unified inactive treatment and explicitly note that the primary-action slot's paused-only swap is preserved as today.
- [x] 10.3 Confirm `docs/main-prd.md` and `docs/tech-design-doc.md` do NOT need updates (no architecture, data-model, sync, or global-constraint changes). Capture this confirmation in the PR description.

## 11. Build, lint, and test (per AGENTS.md > Build and test)

- [x] 11.1 Run `make format`.
- [x] 11.2 Run `make lint-fix`.
- [x] 11.3 Run `make build`.
- [x] 11.4 Run `make test` and confirm all tests pass.

## 12. Cross-cutting concerns confirmation (per docs/main-prd.md §6.8)

- [x] 12.1 **Accessibility** — confirmed: new VoiceOver labels and chip a11y labels added per Tasks 3, 5, 6, 7, 8.
- [x] 12.2 **Localized source strings** — confirmed: all new user-visible strings registered in `Localizable.xcstrings` with translator `comment:` per Task 8.
- [x] 12.3 **Translations queue** — confirmed: `translate-new-strings` runs as Task 8.2 to fan out to all 38 locales.
- [x] 12.4 **Mixpanel user-action analytics** — N/A: this change is presentation-only and adds no user-action events. Existing `budget_paused` / `budget_resumed` events are untouched (Pause/Resume actions live in `BudgetDetailView` action gating, not in the presentation pieces this change modifies).
