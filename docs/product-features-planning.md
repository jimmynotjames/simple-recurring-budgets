# Product Features Planning

**Version:** 1.3  
**Last Updated:** 2026-06-11
**Author/Owner:** Jimmy Ho

For north-star vision, guiding principles, and global constraints, see [main-prd.md](main-prd.md).

### Revision history

| Version | Date       | Author   | Changes |
| ------- | ---------- | -------- | ------- |
| 1.3     | 2026-06-11 | Jimmy Ho | Docs-vs-code audit fixes: F-3.03 locale count 38 → 49 (status prose and AC) to match the 2026-06 locale expansion; canonical storefront list remains PRD §6.8.3. |
| 1.2     | 2026-06-02 | Jimmy Ho | F-6.03 (App Store rating prompt) **Implemented** by change `rating-prompt`: `RatingPromptCoordinator` + KV-backed `RatingPromptState`, Add-mode expense-save trigger hook, root-level `ratingPromptPresenter()`, and the `rating_prompt_eligible` / `rating_prompt_requested` analytics events (pulled forward from F-8.03). Paired with analytics-spec.md v0.15 and tech-design-doc.md §4.5 KV-key additions. |
| 1.1     | 2026-06-02 | Jimmy Ho | F-6.03 (App Store rating prompt) reworked around Apple's native `requestReview`: clarified it uses `@Environment(\.requestReview)` with no custom dialog / pre-prompt; replaced the unworkable "tracks prompt outcomes" AC (the native API has no shown/dismiss/rate callback) with platform-throttling + local once-per-version guard; added positive-moment trigger rule, analytics-consent-independent eligibility counters, the `rating_prompt_eligible` / `rating_prompt_requested` analytics ACs, and a TestFlight-validation note. Finalized the eligibility thresholds (balanced profile: ≥ 7 days installed, ≥ 3 distinct logging days, ≥ 10 lifetime expenses, non-deficit triggering log, once-per-version guard). Paired with analytics-spec.md v0.14 (removed `rating_prompt_shown` / `rating_prompt_resolved`). |
| 1.0     | 2026-05-31 | Jimmy Ho | Synced feature statuses to shipped codebase: F-2.01, F-2.02, F-2.03, F-2.04, and F-3.04 → Implemented; removed stale "budget-calculations rewrite outstanding" status prose; fixed broken links to deleted `budget-calculations-rewrite.md` (now point to `budget-calculations-rewrite-algorithm.md` where retained); F-2.02/F-2.05/F-8.02 prose fixes (Untitled placeholder, seven Settings sections, rewrite analytics events shipped). |
| 0.9     | 2026-05-31 | Jimmy Ho | Retired the `Ongoing` feature status. The four cross-cutting concerns (Dynamic Type, VoiceOver, Dark Mode, Localization, Mixpanel user-action analytics) are no longer tracked as never-completing features here; their per-change maintenance requirements are now canonical in [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns) (§6.8.1–§6.8.4). F-3.01/F-3.02/F-3.03/F-3.05 reframed as completed **initial build-outs** (Status → Implemented), with detailed checklists migrated to the PRD. F-8.02's duplicated "Ongoing concern" sub-bullet removed (it points to §6.8.4). Status legend updated. |
| 0.8     | 2026-05-10 | Jimmy Ho | Synced features list with [`docs/budget-calculations-rewrite.md`](budget-calculations-rewrite.md) (rewrite not yet shipped). Added F-2.08 (Specific Dates budget type) and F-7.07 (Per-budget end date). Updated F-2.01, F-2.02, F-2.03, F-2.04, F-2.07, F-5.01, F-7.05, F-7.06, and F-8.02 ACs / notes to reflect the rewrite's end state: mid-period chip refresh, Specific Dates carve-out, per-budget Start/End Date with weekly/biweekly anchoring, forward-only allocation-edit semantics, Pause / Resume capability, pre-start / post-end / paused chip presentations, expense date-bounds validation, and the new `budget_edited` property flags plus `budget_paused` / `budget_resumed` events. F-2.03 Reset Cadence picker permanently removed (Reset Cadences feature deleted, not paused). F-7.05 and F-7.06 scoped to be marked Implemented when the rewrite ships. |
| 0.7     | 2026-05-03 | Jimmy Ho | F-3.03 → Ongoing. Translations for all 38 storefront locales now complete and merged; both source-string keying and running `scripts/translate_catalog/` are ongoing concerns per [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns). ACs updated to maintenance checklist. |
| 0.6     | 2026-05-03 | Jimmy Ho | Added Status legend (Open / Partially implemented / Implemented / Ongoing / PAUSED). Updated T-3: F-3.01 and F-3.05 → Ongoing; F-3.02 → Ongoing; F-3.03 description updated to note source-string keying is an ongoing concern per [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns) (F-3.03 split deferred to a separate change). F-8.02 Ongoing-concern sub-bullet added. Cross-cutting concerns governed by [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns). |
| 0.5     | 2026-05-02 | Jimmy Ho | (prior history not recorded) |

---

## Status legend

| Status | Meaning |
|--------|---------|
| `Open` | Not started. |
| `Partially implemented` | Feature has a defined end state but is not fully shipped yet. |
| `Implemented` | Feature has reached its defined end state. |
| `Implemented (initial build-out)` | The one-time build-out of a cross-cutting concern (accessibility, dark mode, localization, analytics) is complete. The durable per-change maintenance requirement is canonical in [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns), not tracked here. (Formerly the `Ongoing` status.) |
| `PAUSED` | Explicitly out of scope; retained for future un-pause. |

---

## Themes

### T-1: Technical Foundations

#### Features

##### F-1.01: App Scaffolding

- **Status:** Implemented. Xcode project, test targets, and GitHub repo exist.
- **Description:** Basic app created.
- **Acceptance Criteria:**
  - Xcode project created with main code folder and tests folders scaffolded.
  - git repo created and linked to GitHub
  - Empty app compiles and runs.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-1.02: Data Architecture

- **Status:** Implemented (change `data-architecture`); SwiftData models with CloudKit sync are in place.
- **Description:** Database schema supporting the entire product roadmap. Persistence uses SwiftData with CloudKit sync.
- **Acceptance Criteria:**
  - Database schema instantiated in the app.
  - SwiftData models configured for CloudKit container sync across the user’s devices.
- **Edge Cases / Notes:** None
- **Dependencies:** None

---

### T-2: Fundamentals

#### Features

##### F-2.01: Budgets screen

- **Status:** Implemented. Shipped by changes `budgets-screen`, `finish-budgets-screen`, `rewrite-budget-calculations`, and `unify-inactive-budget-states`.
- **Description:** Top-level screen: list of Budget (entity) rows and where the user stands.
- **Acceptance Criteria:**
  - Name of budget field
  - **For recurring period types** (`daily`, `weekly`, `biweekly`, `monthly`):
    - **Remaining for current Budget Period** field: this period's allocation minus this period's expenses; not merged with carry-over for display (see [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)).
    - **Carry-over** field: separate signed cumulative carryover per [main-prd.md §6.7](main-prd.md#67-carry-over-behavior). The chip refreshes on any change that affects the value (expense add / edit / delete, allocation edit, start/end-date edit, pause/resume, manual reset), not only at period boundaries, and follows the asymmetric live coupling rule (main-prd.md §6.7 "How carry-over moves"): committed overflow from the current period (overspend or add-funds excess) updates Carry-over live; ordinary mid-period slack does not and is folded in only when the period closes. Refresh is driven by user actions and app-lifecycle events (app launch, `scenePhase == .active`); there is intentionally no timer-driven refresh for clock-driven period-boundary crossings.
  - **For the Specific Dates period type** (F-2.08): only the **Remaining** chip is shown, displaying `allocation − sumOfExpensesInWindow`. The **Carry-over** chip is hidden. The Remaining chip freezes after `endDate`.
  - **Inactive presentation**: all three non-running lifecycle states (`.preStart`, `.paused`, `.postEnd`) share one row treatment driven by a view-layer `BudgetInactiveReason` (change `unify-inactive-budget-states`):
    - The large amount renders in `.foregroundStyle(.secondary)` regardless of sign. `.preStart` / `.postEnd` show the budget's allocation; `.paused` shows `remaining` (the calculator's in-period figure).
    - The `RemainingBar` renders as a full-width `.secondary`-filled capsule, not a fraction-driven bar.
    - The status chip area shows a single `InactiveStatusChip` carrying the reason: "Starts {date}" (`calendar.badge.clock`), "Paused · {date}" (`pause.circle.fill`), or "Ended {date}" (`checkmark.circle`).
    - The `CarryOverChip` (when applicable per F-2.01's carry-over rules) still renders, value dimmed to `.secondary`, surplus / deficit capsule tint preserved. Backdated edits to prior active periods can still change the value while the row is inactive.
    - Specific Dates budgets before `startDate` or after `endDate` get the same `.preStart` / `.postEnd` treatment as recurring budgets (one chip, one rule). The `CarryOverChip` stays hidden per F-2.08.
    - The inactive presentation does not affect the row's drill-in tap target, the per-row Add Expense button, or the swipe / reorder affordances.
  - **Drag-to-reorder budgets**: standard iOS edit-mode drag (and long-press drag where the platform supports it); order persists via `Budget.sortOrder`, survives relaunch, and syncs across the user's iCloud-paired devices.
  - This **Budgets screen** is the top level of the app.
- **Edge Cases / Notes:** The Voice query feature (F-7.03) must return the same value the chip displays in every state above.
- **Dependencies:** None

##### F-2.02: Budget screen

- **Status:** Implemented. Shipped by changes `budget-detail-screen`, `expense-row-push-navigation`, `rewrite-budget-calculations`, `pause-resume-budget`, `unify-inactive-budget-states`, and `add-funds-toggle`.
- **Description:** Screen that lists Expense Items for a single Budget (entity).
- **Acceptance Criteria:**
  - Shows vertical scrolling list of transactions as a list of most-recent to least-recent.
  - Shows the Budget's name at top of the screen (navigation title).
  - Shows **Remaining for current Budget Period** and **Carry-over** consistent with [main-prd.md §6.7](main-prd.md#67-carry-over-behavior) and F-2.01. Specific Dates budgets show only the **Remaining** chip (F-2.08); **Carry-over** is hidden.
  - **Mid-period refresh**: Remaining is fully live; Carry-over follows the asymmetric live coupling rule ([main-prd.md §6.7](main-prd.md#67-carry-over-behavior) "How carry-over moves"). Both chips re-evaluate on any change that affects them (expense add / edit / delete, allocation edit, start/end-date edit, pause/resume, manual reset). Refresh is driven by user actions and app-lifecycle events (app launch, `scenePhase == .active`); no timer-driven refresh for clock-driven period-boundary crossings.
  - **Inactive presentation** (status header): all three non-running lifecycle states (`.preStart`, `.paused`, `.postEnd`) share one status-header treatment driven by a view-layer `BudgetInactiveReason` (change `unify-inactive-budget-states`), mirroring the F-2.01 row treatment:
    - The large amount renders in `.foregroundStyle(.secondary)`. `.preStart` / `.postEnd` show the budget's allocation; `.paused` shows `remaining`.
    - The `RemainingBar` renders as a full-width `.secondary`-filled capsule.
    - The header's status chip area shows a single `InactiveStatusChip` carrying the reason: "Starts {date}", "Paused · {date}", or "Ended {date}".
    - The inline `CarryOverChip` (when applicable) still renders, value dimmed to `.secondary`, surplus / deficit capsule tint preserved; the value stays live via backdated edits to prior active periods.
    - The inactive presentation governs presentation only. The primary-action slot's state-driven behavior (Active / Pre-start / Post-end → "Add Expense"; Paused → "Resume Budget" + caption) is unchanged; preStart / postEnd add no new primary-slot variant.
  - **Status header**: large monospaced remaining amount (deficit-tinted when negative), period label, fuel-gauge `RemainingBar`, and, when carry-over is enabled and the period type is recurring, an inline `CarryOverChip`. The manual carry-over reset lives in the toolbar overflow Menu ("Reset Carry-Over…" below), not in a header control.
  - **Adaptive header layout**: remaining amount and period label render side-by-side below `.xxxLarge` Dynamic Type; stacked vertically at `.xxxLarge` and above. Row spacing scales via `@ScaledMetric`.
  - **Primary action slot**: a full-width `.borderedProminent` button whose contents are state-driven:
    - **Active (default):** "Add Expense", presenting `SheetRoute.addExpense(budget)` for this budget.
    - **Paused:** the button is replaced by a "Resume Budget" button that toggles the budget back to active. It is the same action as the toolbar overflow menu item (F-7.06); the prominent slot is for discoverability. A short caption sits directly below the button (e.g., "Paused since {date}. Resume to log expenses."), in `.caption`/`.secondary` styling. The caption is the only paused-state explainer on this surface; there is no separate disabled "Add Expense" affordance.
    - **Pre-start (`now < startDate`) and post-end (`now > endDate`):** "Add Expense" stays active. Future-dated entries within the window (pre-start) and late-logged entries within the window (post-end, including logging trip expenses after returning home for Specific Dates budgets, F-2.08) are legitimate. The Add/Edit Expense sheet clamps the picker's default and shows a short inline caption explaining the constraint (F-2.04 "Date bounds" and "Clamped-default caption").
    - In every state, backdated edits to existing expenses in prior active periods remain available via tap-to-edit on the expense rows (F-2.04 date-bounds rule).
  - **Tap-to-edit expense row**: tapping an expense row pushes `AddEditExpenseView` in Edit mode via `AppRoute.expenseDetail(expense)` (push navigation, standard back-button return). Implemented by change `expense-row-push-navigation`.
  - **Toolbar overflow Menu** (`ellipsis.circle`, top-trailing) hosting:
    - **Edit Budget**: opens the Add/Edit Budget sheet in Edit mode. Available in every lifecycle state.
    - **Pause Budget / Resume Budget**: toggles between paused and active (F-7.06); label and icon reflect the current state. Hidden for Specific Dates budgets (F-2.08); rejected for budgets past `endDate`.
    - **Reset Carry-Over…** (destructive): clears this budget's carry-over balance to zero by setting `lastResetDate = now`. No `ExpenseItem`s are deleted. Hidden when `Budget.isCarryOverEnabled == false`; otherwise visible regardless of the live carry-over magnitude or sign. Available while paused. See [main-prd.md §6.7](main-prd.md#67-carry-over-behavior).
    - **Reset Budget…** (destructive): deletes every `ExpenseItem` for this budget and resets carry-over to zero from that moment forward (storage shape may evolve with the budget-calculations rewrite; user-visible behavior is unchanged). The `Budget` entity is not deleted. Gated by a confirmation dialog whose body is a single static localized string (no expense count in copy). Available while paused; on a paused budget, the same atomic write also inserts a `.resume` `LifecycleEvent` so the post-reset state is active (no paused-but-empty limbo). See [main-prd.md §6.7](main-prd.md#67-carry-over-behavior) for Reset Budget vs Reset Carry-Over vs Delete Budget.
  - **Reset Carry-over** lives in the toolbar overflow Menu as "Reset Carry-Over…", gated by `Budget.isCarryOverEnabled == true`. It presents a single-button destructive confirmation alert; on confirm, only this budget's carry-over is cleared (per [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)). Hidden for Specific Dates budgets (no carry-over). Available while paused.
  - **Delete Expense Item**: swipe-to-delete on a row. A full trailing swipe or a tap on the revealed destructive button deletes immediately; no confirmation dialog.
  - **Period-aware expense sections**: for recurring period types, expenses split into a **Current ⟨period⟩** section (items in the current Budget Period, with a section total) and a **Past ⟨period⟩** section (earlier items). Contextual empty captions cover the current-period-empty and zero-expense cases. Specific Dates budgets render a single section (the entire window is one period).
  - For each Expense Item, shows:
    - Date and time (relative: "Today HH:mm" / "Yesterday HH:mm" / locale-aware beyond yesterday)
    - Amount of expense (absolute value; `Color.moneySurplus` tint for add-funds entries per F-6.01 display path)
    - Name of expense (or an italic "Untitled" placeholder when nil)
  - **Lifecycle refresh** on task initialization, `scenePhase == .active`, and `onChange(of: budget.expenseItems.count)`.
  - **VoiceOver**: composed accessibility labels on the header (on-budget and over-budget variants) and on each expense row (standard and add-funds variants).
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.01

##### F-2.03: Add/Edit Budget screen

- **Status:** Implemented. Shipped by changes `add-edit-budget-screen`, `delete-budget-button`, `restrict-edit-budget-period`, `specific-dates-period`, `finish-start-end-dates`, and `add-orphan-expense-warning`. Uses Foundation's system currency catalog. The Reset Cadences feature is permanently removed; no Reset Cadence control ships in the sheet. The symmetric end-date orphan warning (moving End Date earlier past expenses) is a known deferred gap; the start-date orphan warning shipped.
- **Description:** Screen to create or edit a Budget (entity).
- **Acceptance Criteria:**
  - Same screen used to create and edit.
  - Entry point on the **Budgets screen** to create a Budget (entity).
  - Entry point on the **Budget screen** to edit that Budget (entity).
  - **Delete Budget**: Edit mode only. A destructive bordered button beneath the form cards. Tapping it presents a confirmation dialog ("This action cannot be undone."). Confirming deletes the `Budget` and, via the `Budget → ExpenseItem` cascade-delete rule, all its `ExpenseItem` rows in a single `ModelContext.save()`. The sheet dismisses and the row disappears reactively from the Budgets list. Add mode does not show this button.
  - Fields:
    - ID: Arbitrary internal identifier, not shown to user.
    - Name: defaults to empty string; the field shows `"Budget"` as a placeholder but the draft value is blank, so Save is disabled until the user types a name. In Add mode the Name field auto-focuses (keyboard appears) when the sheet opens.
    - **Period type** (`daily`, `weekly`, `biweekly`, `monthly`, `specificDates`). Defaults to `daily`. **Immutable after creation** for every option (including `specificDates`). In Edit mode the period chips are non-interactive (static labels, not buttons) with a muted style; a `lock.fill` caption ("Period type can't be changed after creating your budget.") appears below the chip grid. The caption names the period type specifically because Start/End dates remain editable in Edit mode for every period type. The model layer also excludes `period` from the fields written on Edit-mode Save, so period cannot be mutated regardless of UI or programmatic state. (For `specificDates` semantics see F-2.08.)
    - **Start Date**: required for every period type. Editable in Add and Edit modes. Add-mode pre-population by period type:
      - **Daily**: today.
      - **Weekly / biweekly**: the latest natural anchor implied by `AppSettings.weekStartDay` (the most recent past or current `weekStartDay`-aligned date). For biweekly budgets the saved `startDate` is the cycle anchor (`biweeklyAnchor` = `startDate`). Weekly budgets grid on the global `AppSettings.weekStartDay` at math-time (change `weekly-global-week-start`, F-5.01); a weekly `startDate` off that grid clips the first period without proration. In Add mode, if the user changes the global week-start mid-create via the in-form Start of Week picker (F-5.01, change `weekly-week-start-from-budget-form`), the weekly draft's `startDate` re-anchors to the most-recent-past occurrence of the new week-start (`AddEditBudgetViewModel.realignWeeklyStartDate(to:)`). The re-anchor is Add-mode and weekly only; it is a no-op in Edit mode (the existing `startDate` is user data) and for non-weekly periods.
      - **Monthly**: the start of the current month.
      - **Specific Dates**: left blank; the user must fill it in before Save is enabled.
      - The user may accept or override the pre-populated value (except Specific Dates, which has none).
      - **Orphan-expense warning (recurring period types, Edit mode):** when the user moves Start Date forward past existing expenses, those expenses become orphaned: still visible in the Budget Detail expense list but excluded from carry-over and remaining (the calculator filters by `effectiveStartDate`). Consequences are surfaced two ways: (a) an inline `.caption` warning inside the expanded Schedule disclosure while the draft is in the orphaning state, and (b) tapping Save presents a confirmation alert (`"Start date is after N logged expenses"` / `"Those expenses still show in your list but won't be counted by this budget."` / `Cancel` · `Save Changes`); confirming saves unchanged, cancelling preserves the draft. On re-open, if a budget is already orphaned, the Schedule disclosure auto-expands. Shipped by change `add-orphan-expense-warning`. The symmetric End Date case is a known parallel gap, deferred.
      - **Biweekly start-date UX (Edit + Add):** biweekly is the only recurring period whose 14-day grid is anchored to the budget's own `startDate` (see F-7.05; daily resets daily, weekly grids on the global Week-Starts-On setting per F-5.01, monthly on the calendar month), so the start date is surfaced and its consequence made explicit:
        - **Explanatory note**: when Biweekly is selected, a `.caption` note ("Repeating 14-day period. Choose your start date below to choose which day each cycle begins on.") renders under the period chips in Add and Edit modes.
        - **Schedule auto-expand**: selecting Biweekly (or opening Edit on a biweekly budget) auto-expands the Schedule disclosure so the cycle anchor is visible; auto-expand only, never auto-collapse.
        - **Save-time re-anchor confirmation**: in Edit mode, when a biweekly budget's Start Date changes, tapping Save presents a confirmation ("Change Start Date?" / "This will re-align current and future two-week cycles and recalculate past periods." / `Cancel` · `Change`), since the edit re-anchors the grid and recomputes past periods (and carry-over). When the same edit also strands expenses, the orphan sentence folds into this alert (it supersedes the standalone orphan warning for biweekly). Shipped by change `biweekly-startdate-ux`.
    - **End Date**: see F-7.07. Optional for recurring period types; required for `specificDates` (Save is disabled until both Start Date and End Date are set). After `endDate`, the chip is frozen at the final tally; the user may still log expenses dated within `[startDate, endDate]` (F-2.04 date-bounds rule).
    - Allocation. Defaults to blank; Save stays disabled until a positive amount is entered. The Allocation card prefixes the numeric field with a currency symbol/code label driven by `AppSettings.currencyDisplay` (symbol / code / code+symbol). **Allocation-edit semantics (recurring period types):** edits are forward-only and effective at `currentPeriodStart` (the boundary of the period in progress). Prior completed periods keep the allocation in effect when they occurred. An allocation edit is not a reset. Edits made while a budget is paused take effect at the resume point (they apply to the period containing the Resume action and every later active period). "While paused" begins at the pause moment per the moment-granular UI semantics in F-7.06, not at the next period boundary. **Specific Dates exception:** a Specific Dates budget has one period (the entire window), so a mid-window allocation edit applies to the entire window; latest-wins overwrites the prior figure (F-2.08).
    - **Currency (per budget)**: each Budget has its own currency. Defaults to the locale's currency; USD if undeterminable.
    - **Carry-over toggle**: see F-2.07. Hidden for `specificDates`; the algorithm ignores `isCarryOverEnabled` for that type.
- **Edge Cases / Notes:** Reset Cadences is permanently deleted by the budget-calculations rewrite (not paused). The `ResetCadence` enum, `Budget.resetCadence`, the `BudgetPeriod.defaultResetCadence` mapping, the scheduled-reset code path in `BudgetLifecycleService`, and any cadence-picker UI hooks are all removed. **Manual Reset Carry-Over**, **Reset Budget**, and **Delete Budget** stay (F-2.02 and [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)).
- **Dependencies:** F-2.01

##### F-2.04: Add/Edit/View Expense Item screen

- **Status:** Implemented. Shipped by changes `add-edit-expense-screen`, `edit-expense-omit-cancel`, `rewrite-budget-calculations`, `finish-start-end-dates`, and `finish-recently-used-expenses`.
- **Description:** A full screen (or partial screen) that shows all the editable fields of an Expense Item (entity).
- **Acceptance Criteria:**
  - Shows editable name of expense (optional)
  - Shows editable amount of expense (required)
  - Shows date and time. **Add-mode default:** the current date/time, clamped into the allowed range: `startDate` if `now < startDate` (minimum), `endDate` if `now > endDate` (maximum). **Edit-mode default:** the existing expense's stored date/time.
  - **Date bounds**: the date picker constrains selection to `[Budget.startDate, Budget.endDate]` ∩ the union of the budget's active periods (active period defined by pause/resume history, F-7.06). For paused budgets, the picker's upper bound is the most recent `.pause` event's `effectiveDate` (the precise moment), which permits same-period-before-pause-moment entries (a 9 AM coffee can still be logged after pausing at 11 AM the same day). Out-of-range dates are either not offered by the picker or rejected on Save. For Specific Dates budgets (F-2.08), this collapses to `[startDate, endDate]`.
  - **Clamped-default caption**: in Add mode, when the budget is pre-start (`now < startDate`) or post-end (`now > endDate`), a short caption renders directly below the date picker in `.caption`/`.secondary` styling so the user understands why the default isn't today. Suggested copy: "Budget starts on {startDate}." (pre-start) or "Budget ended on {endDate}." (post-end), kept deliberately terse. The caption is present for the sheet's entire lifetime while the budget is in that state, not gated on whether the field still shows the clamped value, since the constraint still applies after the user edits it. No caption in the active window. Paused budgets don't reach this sheet via the primary slot (F-7.06 / F-2.02) and Edit-mode entries carry their stored date, so the caption is Add-mode-only and pre-start/post-end-only.
  - Same screen for add, edit, and view.
  - No Edit Mode. User edits fields in place without toggling modes.
  - **Add mode** shows a leading Cancel button (dismisses without saving) and a trailing Save button.
  - **Edit mode** shows only a trailing Save button; the system back button is the discard path.
- **Edge Cases / Notes:**
  - Edit and View are a single mode (per "No Edit Mode"); fields are always directly editable. "View" means opening the Edit sheet for an existing expense.
  - Save in both modes signs `ExpenseItem.amount` per the draft Add Funds toggle (F-6.01). In Edit mode, an existing add-funds row round-trips with its sign preserved when the toggle is untouched; flipping the toggle (with or without changing the amount) flips the sign on Save.
  - Omitting Cancel in Edit mode avoids redundancy with the back button and reduces toolbar clutter on the narrow pushed view.
- **Dependencies:** F-2.02

##### F-2.05: Settings screen

- **Status:** Implemented (change `settings-screen`).
- **Description:** A modal Settings sheet accessible from the Budgets navigation bar. Contains seven sections with functional controls, a Done button, and no ViewModel (plain SwiftUI view).
- **Acceptance Criteria:**
  - A Settings entry-point button in the canonical location in the Budgets navigation bar; tapping it presents a modal sheet.
  - **Budgets section**: Default Carry-Over toggle bound to `AppSettings.defaultCarryOverEnabled`; see F-2.07 for carry-over semantics.
  - **Calendar section**: Week Starts On picker. Shows a confirmation alert before applying the selected weekday (the alert states the cascade: the change also affects existing weekly budgets and recalculates their past weeks); the confirmed value writes to `AppSettings.weekStartDay`; see F-5.01.
  - **Display section**: Currency Display preference picker bound to `AppSettings.currencyDisplay`. Row labels show `"<option label> — <locale-aware example>"`, the example derived live from `Locale.autoupdatingCurrent` using the canonical `Decimal.formatted(currencyCode:display:locale:)` formatter. The value persists to `NSUbiquitousKeyValueStore` and applies app-wide to all monetary rendering; see F-3.04.
  - **Diagnostics & Analytics section**: Analytics opt-in toggle bound to `AppSettings.analyticsOptIn`; see F-8.02 and [analytics-spec.md](analytics-spec.md).
  - **iCloud Sync Status section**: tri-state row derived from `SyncStatus.rowState`: `.checking` (spinner), `.available` (green checkmark icon, syncing), `.paused` (orange exclamation icon, local-only container despite iCloud sign-in), `.unavailable` (orange x icon, not signed in). The section footer appears only for `.unavailable` and `.paused`; account status is re-queried live on `CKAccountChanged` notifications.
  - **Support section**: "Send Feedback" (opens `mailto:` link), "Rate the App" (invokes `requestReview()`), "Privacy Policy" (opens the privacy policy URL in browser).
  - **About section**: app version and build number from `CFBundleShortVersionString` / `CFBundleVersion`.
  - Done button dismisses the sheet.
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.01, F-2.07, F-3.04, F-5.01

##### F-2.06: First-run empty state

- **Status:** Implemented. Included in the `budgets-screen` change (ContentUnavailableView with create-budget CTA).
- **Description:** On first launch with no budgets in the data store, the **Budgets screen** shows a first-run empty state with a clear primary action to create a budget. The app inserts no placeholder or seed Budget.
- **Acceptance Criteria:**
  - After first launch with an empty store, the **Budgets screen** shows its empty-state view (title, short description, primary "Create a budget" CTA), not a blank or unlabeled screen.
  - The app creates no `Budget` entity at launch; any Budget in the store was created by the user.
  - The empty state renders whenever the Budgets `@Query` returns zero rows, so the same view shows for any state where the store transiently has zero budgets (e.g., initial CloudKit hydration on a fresh install of an existing iCloud account).
- **Edge Cases / Notes:** The empty-state UI ships under F-2.01; F-2.06 is the first-launch contract.
- **Dependencies:** F-2.01

##### F-2.07: Carry-over toggle switch

- **Status:** Implemented. Per-budget toggle shipped with `add-edit-budget-screen`; global default shipped with the Settings screen. The Specific Dates carve-out (toggle hidden on Add/Edit Budget, chip hidden on Budgets list and Budget detail) shipped with `specific-dates-period` (F-2.08).
- **Description:** Every **recurring** budget can have the carry-over calculation turned off. Carry-over is meaningless for Specific Dates budgets, so the toggle is hidden in the Add/Edit Budget UI for that period type and the algorithm ignores `isCarryOverEnabled` for it (F-2.08).
- **Acceptance Criteria:**
  - Add/Edit Budget screen has a toggle to turn carry-over of prior balances on/off for recurring period types. Hidden for Specific Dates budgets.
  - In Add mode, the toggle defaults to the global default carry-over setting (`AppSettings.defaultCarryOverEnabled`).
  - Settings has a global setting to default all new Budgets with carry-over on or off. On by default.
  - The setting is stored in `NSUbiquitousKeyValueStore` and syncs across the user's iCloud-connected devices.
- **Edge Cases / Notes:** None
- **Dependencies:** F-1.02, F-2.02, F-2.05

##### F-2.08: Specific Dates budget type

- **Status:** Implemented (change `specific-dates-period`). The `BudgetPeriod.specificDates` case, schema (`Budget.endDate`), and algorithm (`BudgetCalculator.specificDatesBranch`) shipped with the budget-calculations rewrite; the Add/Edit Budget UI, list / detail-screen carve-outs (carry-over chip hidden, Reset Carry-Over and Pause/Resume hidden), latest-wins allocation edit, expense date-bounds clamping, and `Budget.periodDisplayLabel` (date-range label) ship with `specific-dates-period`.
- **Description:** A one-shot / trip-style envelope budget. One window (`[startDate, endDate]`, both required), one allocation for the entire window, no recurrence. Example: "$350 total for the trip." Distinct from a recurring `daily` budget with `startDate` and `endDate` set ("$50/day for 7 days" is a `daily` budget).
- **Acceptance Criteria:**
  - A new `BudgetPeriod.specificDates` case is selectable in the Add/Edit Budget period chip group (F-2.03). Like the other period types, it is immutable after creation.
  - **Required fields:** both `startDate` and `endDate` must be set before Save is enabled. Neither is pre-populated.
  - **Allocation semantics:** a single allocation applies to the whole window; no per-period allocation. Mid-window edits use **latest-wins** (the new value applies to the entire window; the prior figure is not retrievable). This is the documented exception to the forward-only allocation-edit rule in F-2.03.
  - **Chip display:** the **Remaining** chip is shown and displays `allocation − sumOfExpensesInWindow`. The signed cumulative **Carry-over** chip is hidden on both the Budgets screen and Budget detail screen (F-2.01, F-2.02). The Remaining chip freezes after `endDate`.
  - **`isCarryOverEnabled` toggle:** hidden in the Add/Edit Budget UI for this type (F-2.07). The algorithm ignores `isCarryOverEnabled` for this type even if a value is somehow stored.
  - **Reset Carry-Over action:** hidden on Budget detail for this type. The algorithm ignores any reset-carry-over event for this type.
  - **Pause / Resume action:** hidden on Budget detail for this type (F-7.06). If a pause or resume event lands on a Specific Dates budget anyway (direct CloudKit write, UI bug), the algorithm ignores it.
  - **Expense date bounds:** the Add/Edit Expense date picker is constrained to `[startDate, endDate]` (F-2.04). The user may add expenses dated within the window even after `endDate` has passed (e.g., logging trip expenses after returning home).
  - **Add Funds (F-6.01):** negative-amount expenses are supported in Specific Dates budgets and treated as any other expense by the algorithm.
- **Edge Cases / Notes:**
  - Before `startDate`: the chip uses the same "Starts on X" treatment as recurring budgets (F-2.01); the value is 0.
  - After `endDate`: the chip is frozen at the final tally; expense edits within `[startDate, endDate]` still update the displayed value.
  - Backdated expense edits are trivial because the entire budget is one period (no propagation across periods).
- **Dependencies:** F-2.01, F-2.02, F-2.03

---

### T-3: Internationalization and Accessibility

#### Features

##### F-3.01: Dynamic Type — initial build-out

- **Status:** Implemented. The one-time build-out is complete: all shipped screens use semantic text styles, `@ScaledMetric`, and adaptive layouts. The per-change maintenance requirement is in [main-prd.md §6.8.1](main-prd.md#68-cross-cutting-ongoing-concerns); this entry covers only the build-out.
- **Description:** Dynamic Type support built out across every screen shipped to date. Ongoing maintenance (every new UI surface) is a cross-cutting requirement (PRD §6.8.1), not this entry.
- **Acceptance Criteria (initial build-out — all met):**
  - Semantic system text styles throughout; no fixed point sizes.
  - `@ScaledMetric` for custom spacing / dimensions that scale with type size.
  - Layouts verified usable and readable at `.xxxLarge` accessibility size on shipped screens.
- **Edge Cases / Notes:** Per-change maintenance checklist migrated to PRD §6.8.1.
- **Dependencies:** None

##### F-3.02: VoiceOver — initial build-out

- **Status:** Implemented. The one-time build-out is complete: all shipped screens were audited and remediated under [docs/audits/localization+voiceover-audit-2026-04-30.md](audits/localization+voiceover-audit-2026-04-30.md) (full interactive hardware walkthrough is delegated to the human verifier). The per-change maintenance requirement is in [main-prd.md §6.8.1](main-prd.md#68-cross-cutting-ongoing-concerns); this entry covers only the build-out.
- **Description:** VoiceOver support built out across every screen shipped to date. Ongoing maintenance (every new UI surface) is a cross-cutting requirement (PRD §6.8.1), not this entry.
- **Acceptance Criteria (initial build-out — all met):**
  - All shipped interactive and informational elements carry meaningful `.accessibilityLabel` values.
  - Custom composite views collapse to a single VoiceOver element; section headings expose the `.isHeader` trait; destructive controls carry consequence-describing hints; `swipeActions` are mirrored by `.accessibilityAction(named:)`.
- **Edge Cases / Notes:** Per-change maintenance checklist migrated to PRD §6.8.1. Live VoiceOver walkthrough and pseudo-loc smoke procedures are in [Appendices B and C of the audit](audits/localization+voiceover-audit-2026-04-30.md).
- **Dependencies:** F-3.03

##### F-3.03: Internationalization of text — initial build-out

- **Status:** Implemented. The one-time build-out is complete: English source coverage was keyed and audited under [docs/audits/localization+voiceover-audit-2026-04-30.md](audits/localization+voiceover-audit-2026-04-30.md), and translations for all 49 App Store storefront locales are complete and merged (38 at the initial build-out, 49 after the 2026-06 locale expansion). The per-change maintenance requirement (key every new string, re-run the translation pipeline) is in [main-prd.md §6.8.3](main-prd.md#68-cross-cutting-ongoing-concerns); this entry covers only the build-out.
- **Description:** All user-facing text shipped to date is keyed and translatable; labels follow the device locale. Ongoing maintenance (every new string) is a cross-cutting requirement (PRD §6.8.3), not this entry.
- **Acceptance Criteria (initial build-out — all met):**
  - All shipped user-facing strings use `Text("key", comment:)` or `String(localized: KEY, defaultValue:, comment:)`; no hard-coded English literals; every key carries a translator-friendly `comment:` and the catalog has no orphan keys.
  - All 49 storefront locales have translations for all catalog keys (produced via `scripts/translate_catalog/`). The canonical storefront list is in PRD §6.8.3.
- **Edge Cases / Notes:** Per-change maintenance checklist and storefront list migrated to PRD §6.8.3. Pseudo-localization smoke procedure in [Appendix B of the audit](audits/localization+voiceover-audit-2026-04-30.md); full keying rules in `docs/tech-design-doc.md` §5.1.
- **Dependencies:** None

##### F-3.04: Internationalization of currency

- **Status:** Implemented. Per-budget currency picker (`CurrencyPickerView`) and locale-aware formatting shipped with `add-edit-budget-screen`; currency display preference shipped with `settings-screen`. ISO currency display names in the picker come from Foundation (`localizedString(forCurrencyCode:)`) and follow the device locale; catalog-backed UI copy on that flow is covered by F-3.03.
- **Description:** Currency is **per Budget** (entity; see F-2.03), not a global app default. This feature covers formatting, symbols, and the currency catalog used when choosing a Budget’s currency.
- **Acceptance Criteria:**
  - **Add/Edit Budget screen** includes a currency picker with all supported currency codes (not a global override on the **Settings screen**). *(Implemented by `add-edit-budget-screen`.)*
  - Amounts and symbols respect each Budget’s selected currency and the user’s locale formatting rules.
  - The currency catalog (codes, symbols, localized names) comes from outside our application source: Foundation’s system catalog (`Locale.commonISOCurrencyCodes` plus `Locale.localizedString(forCurrencyCode:)`) or a project-owned data file (e.g. YAML) when the app must diverge from the system catalog. The Add/Edit Budget screen ships the system-catalog path.
  - The display name of each currency in the picker is internationalized. *(Implemented by `add-edit-budget-screen`.)*
  - **Changing a Budget's currency is a label change only; no FX conversion is applied to `Budget.allocation` or any `ExpenseItem.amount`.** The Add/Edit Budget screen shows an inline caption ("Changing currency only updates the label. I.e. No currency conversion.") below the allocation/currency row whenever the picked currency differs from the one at sheet-open. *(Implemented by `restrict-edit-budget-period`.)*
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.03, F-3.03

##### F-3.05: Dark Mode — initial build-out

- **Status:** Implemented. The one-time build-out is complete: named color assets with separate light/dark appearances and semantic system colors are used throughout all shipped screens. The per-change maintenance requirement is in [main-prd.md §6.8.2](main-prd.md#68-cross-cutting-ongoing-concerns); this entry covers only the build-out.
- **Description:** Dark Mode support built out across every screen shipped to date. Ongoing maintenance (every new UI surface) is a cross-cutting requirement (PRD §6.8.2), not this entry.
- **Acceptance Criteria (initial build-out — all met):**
  - Named color assets from `Resources/Assets.xcassets` with separate light/dark appearances for all custom colors; semantic system colors throughout; no hard-coded color literals (permitted system-palette exceptions documented in PRD §6.8.2 and `docs/tech-design-doc.md` §5.5).
- **Edge Cases / Notes:** Per-change maintenance checklist migrated to PRD §6.8.2.
- **Dependencies:** None

---

### T-4: Cute Shit

#### Features

##### F-4.01: Technical - Refactor support multiple color themes.

- **Status:** Open
- **Description:** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.02: Support multiple color themes

- **Status:** Open
- **Description: For example, feminine, masculine, dogs, cats, whatever.** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.03: Support an icon for each Budget

- **Status:** Implemented (change `budget-icon-emoji`). Scoped to a single emoji chosen from the app's curated set. Alternative icon sources were canceled (see "Descoped").
- **Description:** User can pick an optional icon to distinguish each Budget. The icon is a single emoji from a curated set the app provides.
- **Acceptance Criteria:**
  - **Add/Edit Budget screen** offers icon selection: a picker presenting the curated emoji set. Choosing is optional.
  - **Budgets screen** and **Budget detail screen** display the chosen icon (when set) ahead of the budget name, as a leading view (an `HStack` element, not a string prefix) so it sits on the leading edge and mirrors in RTL. On the detail screen the icon + name is a scroll-aware content-area large title that wraps long names and collapses into the inline nav bar (issue #117), not a string `navigationTitle`.
  - The icon is stored as a single optional `String` on the `Budget` entity (`Budget.icon`); `nil` when unset.
  - The curated emoji set lives in code; the picker component is the master source. Do not enumerate the set in this doc (it will drift); read the code.
- **Descoped (canceled — will not implement):** Deliberately dropped (not deferred) when the feature was scoped to the curated emoji set. Not on the roadmap:
  - SF Symbols / a symbol picker as an icon source.
  - Genmoji or other Apple-native custom-generated emoji-like icons.
  - LLM-guessed default-icon suggestion.
  - Photo upload as an icon (was F-4.04, canceled; see below).
- **Edge Cases / Notes:** The icon is decorative; VoiceOver announces the budget name without it. A budget with no icon renders name-only.
- **Dependencies:**

##### F-4.04: Support for photo upload for icon for each Budget

- **Status:** Canceled (descoped). Budget icons are scoped to the curated emoji set (F-4.03); photo upload will not be implemented. The heading is retained so the ID isn't reused and the decision is on record.
- **Description:** ~~Photo upload as a Budget icon.~~ Canceled; Budget icons are a single emoji per F-4.03.
- **Acceptance Criteria:** —
- **Edge Cases / Notes:** —
- **Dependencies:**

---

### T-5: Configurations

#### Features

##### F-5.01: Configurable start of week.

- **Status:** Implemented. `AppSettings.weekStartDay` with Settings picker and confirmation alert (change `settings-screen`). Global-grid scope (below) shipped with `weekly-global-week-start` (issue #240), reversing the per-budget-anchor scope that shipped with `rewrite-budget-calculations`. A second entry point (Add/Edit Budget weekly disclosure note + in-form Start of Week picker) shipped with `weekly-week-start-from-budget-form`.
- **Description:** Choose the start day of week. The setting defines the **global weekly grid**: every weekly Budget's periods roll on this weekday, as every monthly Budget shares the calendar-month grid.
- **Acceptance Criteria:**
  - Default is the locale's official week starting day (e.g., Sunday in the USA, Monday in most of Europe).
  - Configurable to be different.
  - **Scope:** the setting is consulted at math-time for all weekly budgets. `BudgetCalculator.snapshot` and the `BudgetLifecycleService` entry points take it as an explicit `weekStart` parameter (no default); view call sites pass `settings.weekStartDay`. Changing it immediately re-grids every weekly budget, past periods included: historical per-week sums regroup and carry-over recomputes (the confirmation alert says so). A weekly `startDate` off the grid only clips the budget's first period (full allocation, no proration). **Biweekly budgets are unaffected**: their 14-day cycle stays anchored to their own `startDate` (a weekday cannot define the cycle's phase). The setting still seeds the pre-populated `Start Date` for new weekly/biweekly budgets (F-2.03).
  - Stored in `NSUbiquitousKeyValueStore`; syncs across the user's iCloud-connected devices. Budgets-list rows and Budget detail refresh on `onChange(of: settings.weekStartDay)`, so local and remote-synced changes re-grid visible budgets immediately.
  - **Entry points:** two surfaces: (1) Settings → Calendar "Week Starts On" menu picker; (2) the Add/Edit Budget screen, where selecting Weekly reveals a disclosure note ("All weekly budgets start on `<day>`.") with a "Change start of week" link that pushes a focused Start of Week screen (`WeekStartPickerScreen`) onto the form's own navigation stack (the in-progress draft is preserved). Both write the same global `AppSettings.weekStartDay` behind the same cascade-warning confirmation (`WeekStartConfirmation` + the shared `settings.weekStart.alert.*` strings) and fire the same `setting_changed` (`week_start_day`) analytics; the focused screen carries an app-wide-scope banner so its global reach is unambiguous. The two surfaces intentionally use different layouts (menu picker vs. full-screen list).
- **Edge Cases / Notes:**
- **Dependencies:**

---

### T-6: Miscellaneous

#### Features

##### F-6.01: Allow manually adding funds

- **Status:** Implemented. Model layer (`isAddFunds`, `displayAmount` on `ExpenseItem`, negative-amount convention) and Budget-detail row display (green tint, distinct VoiceOver label) shipped earlier. The Add/Edit Expense form's Add Funds toggle, sign-on-save in Add mode, toggle-aware sign in Edit mode (including type-flipping an existing entry), navigation-title flip, amount-text tint, and "Add funds" Description default seed shipped with change `add-funds-toggle`.
- **Description:** User can add a transaction whose amount adds to available funds instead of subtracting from it.
- **Acceptance Criteria:**
  - The Add/Edit Expense form includes a discrete `Toggle("Add funds")` card as the fourth card (after Amount / Description / When, before the Delete button in Edit mode) with `.tint(.accentColor)` and an explanatory caption ("Adds to your remaining balance instead of subtracting.").
  - When the toggle is on, the navigation title swaps from "Add Expense" → "Add Funds" (Add mode) and "Expense" → "Add Funds" (Edit mode). The Edit-mode title intentionally matches Add mode even though it breaks the Expense/Add Expense symmetry: "Funds" alone reads as an awkward noun-form title, while "Add Funds" is unambiguous in both contexts.
  - When the toggle is on, the Amount card's currency-prefix text and numeric field render in `Color.moneySurplus` (matching add-funds rows in the Budget detail list). When off, default colors.
  - Toggling off → on with an empty/whitespace Description seeds it with the localized default "Add funds". The seed is one-way: toggling back off does not clear the field, and a later on transition with a non-empty Description does not overwrite. The seed never fires on Edit-mode init (existing rows keep their persisted name).
  - Save in Add mode signs the inserted `ExpenseItem.amount` per the toggle (`signedAmount = isAddFunds ? -amount : amount`). The visible Amount field stays a non-negative numeric editor in every state.
  - Save in Edit mode reads the **draft** `isAddFunds` (not the persisted `expense.isAddFunds`) when applying the sign, so flipping the toggle persists the sign flip. A standalone toggle flip with no other field change still counts as a change: it flips the sign of `expense.amount`, bumps `lastModified`, and triggers exactly one `context.save()` and one `expense_edited` analytics event.
  - Tap-to-edit on an existing add-funds row in the Budget detail list reopens the sheet with the toggle on, the amount tinted, and the title "Add Funds", round-tripping the persisted sign.
  - Analytics: the existing `AnalyticsProperty.isAddFunds` on `expense_logged` / `expense_edited` / `expense_deleted` reflects the toggle-driven sign in both modes; no new events or properties.
- **Edge Cases / Notes:**
  - The placeholder for an unnamed row is "Untitled" (key `budgetDetail.expenseRow.unnamed`, formerly "Untitled expense") so one key reads naturally for both transaction types.
  - There is no second entry point on the Budget detail or Budgets list (e.g., a toolbar "Add Funds…" menu item). The in-form toggle is the single discrete affordance (frequency-matched placement); the title flip, amount tint, and description seed provide the discoverability feedback.
- **Dependencies:** F-2.02 (Budget detail surfaces row display), F-2.04 (Add/Edit Expense screen).

##### F-6.02: Expense Type on Expense Items

- **Status:** Partially implemented. Schema done: `expenseType: String?` on `ExpenseItem` (persisted in SchemaV1). No user-facing editor shipped yet.
- **Description:** 
  - On each Expense Item, allow user to specify an Expense Type.  
  - User can select from "Cash", "Credit Card", "Debit Card", but can also choose to type in their own value.
  - If user types in own value, that is stored as a predefined value in the future.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-6.03: App Store rating prompt

- **Status:** Implemented (change `rating-prompt`). `RatingPromptCoordinator` + KV-backed `RatingPromptState` own the eligibility logic; the trigger hooks into the Add-mode expense-save path (`AddEditExpenseView+RatingPrompt.swift`), and the native `requestReview` is presented from a root-level `ratingPromptPresenter()` modifier after the Add Expense sheet dismisses.
- **Description:** Prompt the user to rate the app in the App Store after meaningful product use and/or a minimum elapsed time. Settings already exposes a manual **Rate the App** control (`requestReview()`); this feature covers **automatic** eligibility-based prompting. Both paths use Apple's native `requestReview` (`@Environment(\.requestReview)`); we build no custom rating dialog or "do you like the app?" pre-prompt (review-gating hurts ratings and conflicts with the no-engagement-pressure constraint in [main-prd.md §3](main-prd.md) / [ux-design-brief.md](ux-design-brief.md)).
- **Acceptance Criteria:**
  - The app calls `requestReview` only after eligibility conditions are met and only at a positive moment: never on launch, mid-task, or on a destructive or over-budget moment.
  - **Trigger point:** evaluated immediately after a successful **expense log (Add mode)** whose resulting Remaining for the period is **≥ 0** (non-deficit). Edits, deletes, add-funds, and destructive actions are not trigger points.
  - **Eligibility gate (balanced profile — all must hold):**
    - Install age **≥ 7 days**.
    - **≥ 3 distinct calendar days** on which an expense was logged.
    - **≥ 10 expenses** logged lifetime.
    - The triggering log left the period **non-deficit** (Remaining ≥ 0).
    - The app has **not already requested a review for the current app version** (local once-per-version guard).
  - **Re-prompt prevention relies on the platform, not on observing the result.** Apple's native `requestReview` throttles to at most 3 prompts per user per 365-day window and suppresses re-prompts for an app version already acted on; the app adds a local once-per-app-version guard. The native API reports neither whether StoreKit presented the dialog nor the user's choice (no callback), so no logic may depend on a prompt "outcome".
  - **Eligibility counters are not gated behind analytics consent.** Install date and usage counters are stored in `UserDefaults` / `NSUbiquitousKeyValueStore` (not `AppSettings.analyticsFirstOpenAt`, which is analytics-gated), so eligibility works identically for users who declined analytics.
  - Prompting is respectful and non-intrusive (not too frequent, not on every launch).
  - **Analytics:** instrument `rating_prompt_eligible` (once per user, when the threshold is first met) and `rating_prompt_requested` (when the app calls `requestReview`), per [analytics-spec.md](analytics-spec.md) §4.4 / §12 / §13. The unobservable `rating_prompt_shown` / `rating_prompt_resolved` events were removed from the spec; do not reintroduce them. These two events were pulled forward from Phase 2 (F-8.03) and ship with `rating-prompt`.
- **Edge Cases / Notes:**
  - Cooldown is platform-managed (≤ 3 / year, suppressed per acted-on version) plus the local once-per-version guard. No app-defined cooldown timer.
  - The balanced-profile thresholds are intentionally simple, fixed constants. If Phase 2 analytics (`rating_prompt_eligible`) shows users hit eligibility too early or too rarely, revisit the numbers (a one-line change); they are a candidate for the F-8.03 feature-flag seam ([analytics-spec.md](analytics-spec.md) §15).
  - The native rating dialog never appears in TestFlight builds, so the prompt can only be validated in App Store builds; the eligibility/trigger logic is what gets unit-tested.
- **Dependencies:** None

---

### T-7: Optimizing the UX

#### Features

##### F-7.01: Receipt scanning via camera

- **Status:** Open
- **Description:** User takes a photo of a receipt; on-device machine vision extracts the amount (and optionally merchant name / date) to pre-fill an Expense Item.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.04

##### F-7.02: Voice input to add an Expense Item

- **Status:** Open
- **Description:** User speaks via Siri and/or in-app voice input; Apple's on-device NLP parses the utterance into an Expense Item (amount, name, date/time).
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.04

##### F-7.03: Voice query for Budget status

- **Status:** Open
- **Description:** User speaks via Siri and/or in-app voice input to ask about a Budget's current status; the app responds with the **Remaining for current Budget Period** amount and the separate **Carry-over** amount.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.01, F-2.02

##### F-7.04: Recently used expenses

- **Status:** Implemented (change `finish-recently-used-expenses`). Reworked by `recents-rework-spec-sync` (placement below Description, recurrence-gated amount variants, corpus/display cap split, amount-provenance smart apply, double-tap full replace, Description clear button). Extended to Edit mode by `recents-in-edit-mode` (blank-Description-gated reveal in Edit/View mode).
- **Description:** Surface the user's recently logged expenses as tappable suggestions in Add Expense (always) and Edit/View Expense (when the Description is or becomes blank), so they can reuse a prior entry (name + amount) with one tap. Serves the "fast logging" signature element (UX brief) and Guiding Principle #2 (minimal user input) for habitual, recurring expenses, and helps refine a blank or mistyped Description when editing.
- **Acceptance Criteria:**
  - **Reuse name + amount, with amount provenance.** Tapping a suggestion populates the name and, when the draft amount is empty or was seeded by a previous tile tap, the amount. A **user-typed amount survives the tap** (fresher intent beats the tile's historical amount; a silent overwrite the user misses before Save is the costly failure). A **double-tap** (or the "Replace amount and description" VoiceOver custom action) fully replaces both fields, overriding provenance. (Amount is the required field and the primary friction-saver; see F-2.04.) In Edit mode, the seeded existing amount counts as user-typed: a single tap fills Description only; the double-tap (or clearing the amount first) also takes the tile's amount.
  - **Fill, don't auto-save.** A tap populates the draft fields and leaves the user on the sheet to review, edit, and Save; it does not log or commit. The amount stays visible and editable so a stale value is caught before Save (Guiding Principle #3, Clarity).
  - **Suggestion → autocomplete on the same surface.** The Recents section renders directly below the Description field (input-above/suggestions-below autocomplete idiom; the Amount card keeps the top slot for amount-first quick logging). As the user types into Description, suggestions narrow to matching recents; the typed query searches the full memoized corpus, not just the visible row. No separate picker mode or screen. Clearing the Description (including via its trailing clear button) restores the unfiltered row.
  - **Per-budget scope.** Suggestions come from the **current budget's** prior expenses only, never cross-budget. Currency is per-budget (main-prd.md §7.2), so a cross-budget amount could surface under the wrong currency; this also keeps suggestions relevant.
  - **No Settings toggle.** Always on and not user-configurable, per UX Simplicity (Guiding Principle #1) and the "Minimal" Settings directive (UX brief). Revisit only if real-world feedback shows a need to disable or clear recents.
  - **Date handling.** A reused entry takes **today's date, clamped to the budget's allowed range** per F-2.04's date-bounds rules; it does not inherit the original expense's date/time.
  - **Edit-mode reveal (blank-Description-gated, persist-once-shown).** In Edit/View mode the Recents section is hidden by default and revealed once the Description draft is blank (trimmed empty), either because the expense opened with a nil/whitespace name or because the user cleared it mid-session. Once revealed, it persists for the sheet's lifetime (one-way latch: it does not hide again when Description becomes non-empty). All Add-mode affordances apply identically once revealed: filter-as-you-type, same tile row, same tap/double-tap semantics.
- **Edge Cases / Notes:**
  - **Ranking.** Recency-driven. Each unique description (case/diacritic-folded) gets a **base tile** carrying its most recent amount; additional **amount-variant tiles** surface only when that exact (name, amount) pair recurred ≥ 3 times (max 2 extras per name, clustered after their base tile), so a two-price regular gets both as one-tap tiles while one-off price jitter stays collapsed. The memoized **search corpus** (cap 200) is decoupled from the **display cap** (30) so typed queries reach beyond the visible row. Constants are pinned by unit test; subject to revision once usage data accrues.
  - **Excluded categories.** Add Funds entries (F-6.01) and unnamed expenses are not suggested.
  - **Empty and no-match presentation.** When the budget has no candidate expenses, the suggestion surface is absent. How a no-match typed query presents is left to the implementation; form stability takes priority over the exact shape of the empty signal.
  - **Long names** are visually bounded so no single entry dominates.
- **Dependencies:** F-2.04

##### F-7.05: Per-budget period start date

- **Status:** Implemented. Schema + algorithm shipped with `rewrite-budget-calculations`; recurring-period UI (collapsed `Schedule` disclosure in Add/Edit Budget), Add-mode per-period-type pre-population, Edit-mode editability, and snapshot-level back-dating coverage shipped with `finish-start-end-dates`.
- **Description:** Each Budget has its own period start date via `Budget.startDate`. It may be in the past (back-filling), today, or in the future. `startDate` defines when the budget's window begins; for biweekly Budgets it is also the cycle anchor (`biweeklyAnchor` = `startDate`). Weekly Budgets grid on the global `AppSettings.weekStartDay` (F-5.01, change `weekly-global-week-start`); a weekly `startDate` off that grid clips the first period without proration, like a monthly Budget created mid-month. The Add/Edit Budget screen pre-populates `startDate` per period type and requires a value before Save.
- **Acceptance Criteria:**
  - See F-2.03 for the **Start Date** field's UI behavior, including per-period-type pre-population and Edit-mode editability.
  - Carry-over does not accumulate before `startDate`. The chip uses a "Starts on X" presentation while `now < startDate` (F-2.01, F-2.02).
  - Expenses dated before `startDate` are rejected by the Add/Edit Expense date picker (F-2.04).
  - No proration of partial first periods. The full per-period allocation applies even if the first period is partial at the boundary.
- **Edge Cases / Notes:**
  - Stored as `Date?` only because CloudKit-synced SwiftData fields must be optional; the UI guarantees a value before Save. A nil at read time (e.g., a malformed sync record) falls back to `createdAt`.
  - Back-dating `startDate` extends the earliest `AllocationChange` row's amount into the back-dated window via the calculator's `allocationInEffect` fallback (see `simple-recurring-budgets/Domain/AllocationInEffect.swift` and `AllocationInEffectTests.noEligibleRow_fallsBackToEarliest`); no `AllocationChange` realignment is needed for recurring period types. Forward-dating works symmetrically: the walker starts at the new later `effectiveStartDate` and the existing `AllocationChange` still satisfies any lookup at or after that date. The Specific Dates path still realigns the most-recent `AllocationChange` per F-2.08 latest-wins semantics.
- **Dependencies:** F-2.03

##### F-7.06: Pause and Resume a Budget

- **Status:** Implemented (changes `pause-resume-budget` and `pause-immediate-feedback`).
- **Description:** Per-budget on/off capability. A user can **Pause** a budget and later **Resume** it, any number of times. While paused, no allocation accrues to new periods; the chip is frozen at the most-recent-pause value (modulo backdated edits to prior active periods); the Budget detail screen's primary Add Expense CTA is replaced by a prominent Resume Budget button (short caption directly below), and Resume is also in the toolbar overflow menu. A paused budget stays visible and clearly marked as paused. Pause and Resume use a **two-clock model**: carry-over math operates at **period granularity** (no proration: the period containing the pause-action contributes allocation and existing expenses to carry-over at period close normally; the resume-action period is fully active), while the UI flips **moment-granular** at pause-tap so the budget appears paused immediately. Pause / Resume is distinct from `endDate`, which is **terminal** (no resume; F-7.07), and from `specificDates`, a single fixed window with no recurrence (F-2.08).
- **Acceptance Criteria:**
  - **Toolbar action**: the Budget detail toolbar overflow menu hosts a **Pause Budget** / **Resume Budget** action that toggles on current state (F-2.02). Hidden for Specific Dates budgets (F-2.08); rejected for budgets past `endDate` (F-7.07).
  - **Prominent Resume CTA when paused**: in addition to the overflow-menu action, the Budget detail primary `.borderedProminent` slot swaps from "Add Expense" to "Resume Budget" while paused (F-2.02 "Primary action slot"). Both perform the same Resume action; the prominent slot drives discoverability and the menu item stays consistent with the other lifecycle actions. A short caption directly below the button (e.g., "Paused since {date}. Resume to log expenses.") is the only paused-state explainer; no separate disabled "Add Expense" button. The swap does not apply on the Budgets list screen (F-2.01), where paused budgets are marked via the chip presentation only.
  - **Two-clock semantics (math vs UI):**
    - **Math (period-granular, no proration):** the period containing the pause-action is active for carry-over math (full allocation, normal carry-over accrual at period close). Periods strictly after it are paused for math (contribute 0 to the walker) until a Resume. The period containing the resume-action is active in full (no proration); carry-over from the most recent pause carries forward into it.
    - **UI (moment-granular):** `BudgetSnapshot.lifecycleState` flips to `.paused` as soon as a `.pause` event's `effectiveDate` is reached. The Budget detail screen swaps to "Resume Budget", the chip dims, and the Add/Edit Expense entry point on the Budgets list constrains the date picker, all from the pause moment, not the next period boundary. `.preStart` and `.postEnd` UI states still take precedence over `.paused`.
  - **Same-period-before-pause-moment backdating:** because the date-picker upper bound is the pause event's `effectiveDate` (the precise moment), a user can still log a forgotten expense dated earlier the same day after pausing. Same-period-after-pause-moment entries are rejected by the picker.
  - **Allocation edits while paused** take effect at the resume point: they apply to the period containing the Resume action and every later active period (F-2.03). "While paused" begins at the pause moment, so an allocation edit between the pause-tap and the next period boundary also defers to resume.
  - **Backdated expenses to prior active periods** are always accepted (paused or active) and recompute the carry-over of the period they fall in; the change propagates forward through all later active periods. While paused, the Add/Edit Expense date picker is constrained to the union of active periods with the pause moment as the upper bound (F-2.04).
  - **Manual Reset Carry-Over** and **Reset Budget** remain available while paused (F-2.02). The Edit Budget sheet stays open.
  - **Paused-state presentation:** on the Budgets screen and Budget detail screen, the chip is visible and clearly marked as paused, and the pause date is surfaced (F-2.01, F-2.02). The value can still change while paused via backdated edits to prior active periods.
  - **Pause before `startDate`:** if Pause is invoked while `startDate` is in the future, the pause is recorded as if it occurred on `startDate`. The pre-start chip presentation holds until `startDate`; from then on the budget is paused until the user resumes.
  - **`endDate` is terminal:** once `endDate` is reached, the budget cannot be resumed. If `endDate` falls inside a paused period, no special handling is needed: the chip is already frozen at the most-recent-pause value, and reaching `endDate` makes that frozen state terminal.
- **Edge Cases / Notes:**
  - Pause / Resume is hidden for `specificDates` budgets. If a pause or resume event lands on a Specific Dates budget anyway (direct CloudKit write, UI bug), the algorithm ignores it.
  - Concurrent Pause on one device and Resume on another via CloudKit must converge cleanly without a "phantom paused period."
  - This feature absorbs the previous F-7.06 ("Stop a Budget") scope.
- **Dependencies:** F-2.01, F-2.02, F-2.03, F-7.05

##### F-7.07: Per-budget end date

- **Status:** Implemented. Schema + algorithm shipped with `rewrite-budget-calculations`; recurring-period optional `endDate` UI (Schedule disclosure chip + "Clear end date" affordance), Specific Dates required `endDate`, and the Add/Edit Expense pre-start / post-end clamped-default caption (F-2.04) shipped with `finish-start-end-dates`, along with the per-field `start_date_changed` / `end_date_changed` flags on `budget_edited` analytics (F-8.02).
- **Description:** Each Budget can have an end date via `Budget.endDate`. After `endDate`, the budget stops calculating and the chip is frozen at the final tally. `endDate` is **terminal** (unlike Pause, which is reversible; F-7.06). Optional for recurring period types; **required** by the UI before Save for Specific Dates budgets (F-2.08).
- **Acceptance Criteria:**
  - See F-2.03 for the **End Date** field's UI behavior in Add and Edit modes.
  - While `now > endDate`, the algorithm uses `endDate` as its effective "now" and the chip uses an "Ended on X" presentation (F-2.01, F-2.02).
  - The user may still add or edit expenses dated within `[startDate, endDate]` after `endDate` has passed (e.g., logging trip expenses after returning home). Expenses outside `[startDate, endDate]` are rejected by the date picker (F-2.04).
  - **No proration** of the final period. If `endDate` falls mid-period (e.g., a monthly budget ending Sept 15), the final period spans `currentPeriodStart` to `endDate` and the full per-period allocation is credited.
  - Resume is rejected once `endDate` has been reached (F-7.06).
- **Edge Cases / Notes:**
  - Stored as `Date?` because it is genuinely optional for recurring budgets; required by the UI only for Specific Dates budgets.
  - If `endDate` falls inside a paused period, no special handling: the chip is already frozen at the most-recent-pause value, and `endDate` makes that state terminal.
  - Editing mirrors F-7.05: `Budget.endDate` is rewritten directly with no `AllocationChange` realignment. Clearing the optional end date on a recurring budget uses the "Clear end date" affordance on the Schedule disclosure.
- **Dependencies:** F-2.03, F-7.05

---

### T-8: Analytics and Observability

#### Features

##### F-8.01: Diagnostic logging via OSLog

- **Status:** Implemented (change `oslog-diagnostic-logging`).
- **Description:** All operational / diagnostic events (container bootstrap, CloudKit sync outcomes, UI traces) are written directly via `OSLog.Logger` constants in [`Logging/AppLoggers.swift`](../simple-recurring-budgets/Logging/AppLoggers.swift). Diagnostic logging never passes through `AnalyticsClient`, which is product-only. Categories are fixed: `bootstrap`, `cloudkit`, `ui` (defined in `AppLoggers.swift`).
- **Acceptance Criteria:**
  - **Bootstrap category** (`Logger.bootstrap`): a single `info`-level entry on app launch indicating the resolved `AppDatabaseLaunchMode` (Release builds always log `.normal`; DEBUG logs the active case from the dev override).
  - **CloudKit category** (`Logger.cloudKit`): retain the existing call sites in `makeProductionModelContainer` (`cloudkit.container.backed` / `localFallback` / `localSuccess` / `failed`); add an entry on `CKAccountChanged` reception in `SettingsView` recording the old → new account status transition for the iCloud sync row (privacy: `.public` for the enum value, never the user's identity).
  - **UI category** (`Logger.ui`): one `debug`-level entry per user-initiated destructive action (`Reset Budget`, `Reset Carry-Over`, `Delete Budget`, `Delete Expense`) recording the entity's `persistentModelID` (privacy: `.private`) and the action name. No entries for non-destructive UI traces in Phase 1 (lean by default); add entries only for a debugging need.
  - **Boundary contract**: no call site under `simple-recurring-budgets/` invokes both `Logger.*` and `AnalyticsClient.track(...)` for the same conceptual event with the intent of cross-routing. (A single user action MAY produce one of each, e.g. a successful Add Expense fires `expense_logged` to Mixpanel and writes a `Logger.ui` entry, but the two calls are independent and the `AnalyticsClient` call is never derived from a `Logger` callback or vice versa.)
  - **Privacy levels**: every `Logger.*` call site that interpolates a value MUST set an explicit `privacy:` argument. Strings derived from user input or model identifiers default to `.private`; static enum values, error descriptions from Apple frameworks, and bundle metadata may be `.public`.
- **Edge Cases / Notes:** The OSLog half of the F-8.01 / F-8.02 split in [analytics-spec.md §17](analytics-spec.md#17-boundary-with-f-801-oslog). It SHOULD ship as its own OpenSpec change before F-8.02 so the boundary exists before any Mixpanel call site is added.
- **Dependencies:** None

##### F-8.02: Mixpanel Phase 1 — foundation and basic stats

- **Status:** Implemented (change `mixpanel-phase-1-foundation`, 2026-05-03). A discrete Phase-1 build-out. The per-change requirement that every new user action ship its analytics event is a cross-cutting concern in [main-prd.md §6.8.4](main-prd.md#68-cross-cutting-ongoing-concerns), not here.
- **Description:** Establish the product analytics foundation: the smallest viable Mixpanel integration that still answers who is using the app, what they use it for, and whether they come back, and that informs future features. Detailed events, properties, dashboards, identity, consent jurisdictions, and architecture live in [analytics-spec.md](analytics-spec.md). Mixpanel is the chosen vendor; rationale and weaknesses we sidestep are in spec §1 (Vendor Choice). The ongoing requirement to instrument every new user action lives in [main-prd.md §6.8.4](main-prd.md#68-cross-cutting-ongoing-concerns).
- **Acceptance Criteria:**
  - **Constraints:** see [analytics-spec.md §2 (Canonical Constraints)](analytics-spec.md#2-canonical-constraints), the single source of truth for the locale-aware consent default, no-PII guarantee, OSLog boundary, copy-keying, and lazy-SDK-init rules that gate this feature.
  - **Product questions Phase 1 must answer:** see [analytics-spec.md §3 (Product Questions — Phase 1)](analytics-spec.md#3-product-questions--phase-1) for the canonical list, and [§11 (Phase 1 Dashboards)](analytics-spec.md#11-phase-1-dashboards) for each question's report. Phase 1 ships only when each §3 question has a dashboard or report in §11.
  - **Deliverables (the spec is the source of truth):**
    - Mixpanel SDK integrated, opt-in toggle in Settings, first-run consent sheet in consent-required jurisdictions, and the canonical event + property surface implemented per [analytics-spec.md](analytics-spec.md).
    - Phase 1 dashboards built and linked from the spec.
    - Companion updates to [tech-design-doc.md](tech-design-doc.md) §§4.5, 7, 9 per spec §19.
- **Edge Cases / Notes:**
  - Mixpanel is **not** a crash reporter or time-series telemetry log; crash and lifecycle data stays on `OSLog` (F-8.01) and Apple-native frameworks (MetricKit). Full F-8.01 boundary: [analytics-spec.md](analytics-spec.md) §17.
  - Final per-event property list, super properties, people properties, and dashboards live in [analytics-spec.md](analytics-spec.md), the implementation contract; this entry is intentionally high-level.
  - **Historical implementation starting state.** Pre-F-8.02 scaffolding refactors are recorded in [analytics-spec.md §16.1](analytics-spec.md#161-implementation-starting-state-codebase-snapshot-historical-record) (historical record). All refactors are complete.
  - **Budget-calculations rewrite analytics** shipped with `rewrite-budget-calculations` and `finish-start-end-dates`: `budget_edited` property flags (`allocation_changed`, `start_date_changed`, `end_date_changed`) and dedicated `budget_paused` / `budget_resumed` events (F-7.06). Cadence-related properties from the deleted Reset Cadences feature were removed from [analytics-spec.md](analytics-spec.md).
- **Dependencies:** F-2.05 (Settings — for the opt-in toggle), F-3.03 (i18n of consent + Settings copy), F-8.01 (OSLog boundary; SHOULD ship before F-8.02)

##### F-8.03: Mixpanel Phase 2 — reactive deepening and experimentation seam

- **Status:** Open
- **Description:** React to what Phase 1 reveals. Add the behavioral depth Phase 1 cannot deliver (funnel drop-offs, cohort retention, whether UX promises such as "fast logging" materialize) and a controlled experimentation seam so small UX experiments (theme defaults, rating-prompt thresholds, copy variants) can run without app updates. The detailed event / property / dashboard surface lives in [analytics-spec.md](analytics-spec.md) §§4, 12–15 and MUST be re-validated against actual Phase 1 evidence before implementation: low-signal Phase 2 properties are dropped or replaced.
- **Acceptance Criteria:**
  - **Constraints:** see [analytics-spec.md §2 (Canonical Constraints)](analytics-spec.md#2-canonical-constraints), sections 2.1 and 2.2. All Phase 1 constraints carry forward; §2.2 adds the Phase-2 feature-flag constraints (pull-only, cached, never blocking launch).
  - **Product questions Phase 2 should answer:** see [analytics-spec.md §4 (Product Questions — Phase 2)](analytics-spec.md#4-product-questions--phase-2) for the canonical list, and [§14 (Phase 2 Dashboards)](analytics-spec.md#14-phase-2-dashboards-planned) for each question's report. Phase 2 scope is re-validated against Phase 1 evidence before implementation; low-signal items are dropped or replaced.
  - **Deliverables (the spec is the source of truth):**
    - Funnel-abandonment events, cohort-driving people properties, and lightweight performance properties implemented per [analytics-spec.md](analytics-spec.md) §§12–14.
    - `FeatureFlagClient` protocol + `MixpanelFeatureFlagClient` and `StaticFeatureFlagClient` implementations per spec §15.
    - Phase 2 dashboards built and linked from the spec.
    - The implementing change cites Phase 1 dashboard evidence motivating (or trimming) each Phase 2 property and event before scope is locked.
- **Edge Cases / Notes:**
  - Phase 2 acceptance criteria predate Phase 1 evidence; the spec's Phase 2 lists are marked **planned** and may shift.
- **Dependencies:** F-8.02

