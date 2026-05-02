## Why

F-8.01 ("Diagnostic logging via OSLog") in [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) is currently only partially implemented: `AppLoggers.swift` defines the three category constants (`bootstrap`, `cloudKit`, `ui`) and four `Logger.cloudKit` call sites exist inside `makeProductionModelContainer`, but the `bootstrap` and `ui` categories have **zero** call sites and there is no codified contract that constrains future call sites. F-8.01 also has to ship before F-8.02 (Mixpanel Phase 1) so the OSLog↔`AnalyticsClient` boundary in [`docs/analytics-spec.md` §17](../../../docs/analytics-spec.md) is established before any product analytics call site is added.

This change closes the gap by adding the missing call sites, codifying the privacy / boundary rules as a first-class capability, and recording in `docs/tech-design-doc.md` §7 that the OSLog category list now matches `AppLoggers.swift` end-to-end. After this change ships, F-8.01 flips to **Implemented** in `product-features-planning.md`.

## What Changes

- Add **`Logger.bootstrap`** call site at app entry: a single `info`-level entry on launch that records the resolved `AppDatabaseLaunchMode` (Release always logs `.normal`; DEBUG logs the active case from the dev override). Privacy `.public` for the enum value.
- Add **`Logger.cloudKit`** call site in `SettingsView.observeAccountChanges` / `loadICloudStatus`: a `notice`-level entry whenever the iCloud account status transitions, recording the `old → new` `AccountStatus` enum values (privacy `.public`). The four existing `Logger.cloudKit` call sites in `makeProductionModelContainer` (`backed` / `localFallback` / `localSuccess` / `failed`) are retained as-is.
- Add **`Logger.ui`** call sites at every user-initiated destructive action call site, each `debug`-level, recording the entity's `persistentModelID` (privacy `.private`) and the static action name (privacy `.public`). The four sites are:
  - `Reset Budget` — `BudgetDetailView.resetBudget`
  - `Reset Carry-Over` — `BudgetDetailView.resetCarryOver`
  - `Delete Budget` — `AddEditBudgetViewModel.delete(context:)`
  - `Delete Expense` — `BudgetDetailView+ExpenseSection.deleteExpense(_:)` (covers both swipe-action and rotor-action paths since both call the same method)
- Codify the **privacy contract** as a structural rule: every `Logger.*` call site that interpolates a value MUST set an explicit `privacy:` argument. Strings derived from user input or `persistentModelID`s default to `.private`; static enum values, error descriptions from Apple frameworks, and bundle metadata may be `.public`.
- Codify the **boundary contract** with `AnalyticsClient` (per `docs/analytics-spec.md` §17): no call site under `simple-recurring-budgets/` invokes both `Logger.*` and `AnalyticsClient.track(...)` for the same conceptual event with the intent of cross-routing. A single user action MAY produce one of each (independently); neither callback is derived from the other.
- Land **Swift Testing** unit tests that assert the boundary contract structurally — there is no helper that routes a `Logger.*` callback into `AnalyticsClient` and vice versa — and that the `AppLoggers` constants exist with the expected categories. (`OSLogStore`-driven assertions on actual emitted log lines are NOT in scope; OSLog read-back is brittle in CI and the contract is structural, not behavioral.)
- Update [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7 to confirm the category list matches `AppLoggers.swift`, list the canonical call-site map, and cross-reference `analytics-spec.md` §17.
- Flip F-8.01 status to **Implemented** in [`docs/product-features-planning.md`](../../../docs/product-features-planning.md).
- Update [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §19 row for "F-8.01 ships" so the doc-update checklist for that row is marked done (no content drift expected; this is a status update only).

## Capabilities

### New Capabilities

- `diagnostic-logging`: Owns the OSLog contract end-to-end — the three categories (`bootstrap`, `cloudKit`, `ui`), the canonical call-site map, the privacy levels (`.public` vs `.private`) per call site, and the structural boundary with `AnalyticsClient`. This capability is the single source of truth for "what we log, where, and at what privacy level." Future features that add a `Logger.*` call site MUST update this spec in the same change.

### Modified Capabilities

None. The four destructive-action call sites live inside views governed by `budget-detail-screen` (`Reset Budget`, `Reset Carry-Over`, `Delete Expense`) and `add-edit-budget-screen` (`Delete Budget`), but the existing screen specs already own those user-visible behaviors; this change adds **diagnostic side-effects** that the new `diagnostic-logging` capability owns. The screen specs do not need delta updates because nothing user-observable changes (no UI, no haptics, no copy). The bootstrap log site lives in `simple_recurring_budgetsApp` and is governed by the new capability directly. The CKAccountChanged log site is inside `SettingsView` and governed by `settings-screen`, but again — nothing user-observable changes; the diagnostic side-effect is owned by the new capability.

## Impact

- **Code**:
  - `simple-recurring-budgets/App/simple_recurring_budgetsApp.swift` — add a `Logger.bootstrap.info(...)` call after `appDatabaseLaunchMode` resolution.
  - `simple-recurring-budgets/Views/SettingsView.swift` — emit `Logger.cloudKit.notice(...)` from `loadICloudStatus()` whenever `accountStatus` transitions.
  - `simple-recurring-budgets/Views/BudgetDetailView.swift` — `Logger.ui.debug(...)` inside `resetBudget` and `resetCarryOver`.
  - `simple-recurring-budgets/Views/BudgetDetailView+ExpenseSection.swift` — `Logger.ui.debug(...)` inside `deleteExpense(_:)`.
  - `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift` — `Logger.ui.debug(...)` inside `delete(context:)`.
  - `simple-recurring-budgetsTests/Logging/` — new Swift Testing suite covering the structural boundary and the `AppLoggers` category contract.
- **Docs**: Update `docs/tech-design-doc.md` §7 (OSLog category list + call-site map cross-reference); flip F-8.01 status in `docs/product-features-planning.md`; mark `docs/analytics-spec.md` §19 F-8.01 row as done.
- **Dependencies**: None added or removed. Pure Apple `OSLog` / `os.Logger` only.
- **Performance**: Negligible. Five `Logger` call sites, all on user-initiated paths or one-time launch.
- **Privacy / security**: All user-derived values (`persistentModelID`) are `.private` interpolations so they appear redacted in the device's unified log unless the user / developer attaches the device for live debugging. No additional data leaves the device. Aligned with [`docs/main-prd.md`](../../../docs/main-prd.md) §6.3 and [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7.
- **Boundary with F-8.02**: This change establishes the OSLog half of the F-8.01 / F-8.02 split. F-8.02 (Mixpanel Phase 1) MUST NOT regress this boundary — see `docs/analytics-spec.md` §17.

## Doc alignment

- [`docs/main-prd.md`](../../../docs/main-prd.md) §6.3 — "Protect user's privacy with the usual Apple tools." This change uses Apple's unified logging with explicit `privacy:` annotations; aligned, no doc update needed.
- [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.01 — current status is "Partially implemented." This change flips it to **Implemented**. The acceptance criteria in F-8.01 are the authoritative requirements list; this proposal implements them verbatim.
- [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7 — already names the three categories. After this change, §7 confirms the category list matches `AppLoggers.swift` end-to-end and points at `analytics-spec.md` §17 for the `AnalyticsClient` boundary. Required update at implementation time per `docs/analytics-spec.md` §19.
- [`docs/ux-design-brief.md`](../../../docs/ux-design-brief.md) — no UX surface changes (no UI, no copy, no haptics). Aligned, no doc update needed.

No conflicts with any of the three governing docs.
