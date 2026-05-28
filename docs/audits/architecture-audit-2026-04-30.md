# Architecture Audit

| Field           | Value      |
|-----------------|------------|
| **Date**        | 2026-04-30 |
| **Codebase**    | 43 source files, 20 test files (Swift Testing) |
| **Stack**       | SwiftUI + SwiftData + CloudKit, latest Swift / iOS |

> This document is a durable reference for AI agents and human developers working in this repo. It describes how the architecture actually works (from code, not just docs), what patterns to follow, what pitfalls to avoid, and what open questions to flag rather than silently resolve.

---

## 1. Executive Summary

Before touching this codebase, know these five things:

1. **The architecture is "View + Services, ViewModels on demand."** Most screens read data via `@Query` or model relationships and delegate logic to pure Domain services. Only screens with non-trivial draft/form state (`AddEditBudgetView`, `AddEditExpenseView`) escalate to an `@Observable` ViewModel. Do not reflexively add a ViewModel for a new screen -- check the escalation criteria in `tech-design-doc.md` section 2.1 first.

2. **~~All persistence saves silently discard errors.~~** **Resolved** by the `robust-persistence-error-handling` OpenSpec change (issue #9, 2026-05-27). Production saves now route through `ModelContext.saveChanges(operation:analytics:)`, which throws a typed `PersistenceError`, logs to `Logger.persistence.error`, and fires the narrow-scoped `persistence_save_failed` analytics event. Interactive screens present the standard `.saveErrorAlert` and do not dismiss on failure. Only `DebugData.swift` and `BudgetDetailFixtures.swift` retain `try?` (preview / dev seed only). The container-creation `fatalError` recovery (originally part of this risk) is resolved separately by the `container-creation-recovery` change (issue #132, 2026-05-28).

3. **`BudgetLifecycleService` is the sole write-back path for carry-over math.** It orchestrates roll -> persist -> reset -> persist -> compute remaining. Screens call `refreshAndSave` eagerly (on `.task`, `scenePhase == .active`, and expense count changes). Do not call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly from views -- always go through `BudgetLifecycleService`.

4. **CloudKit imposes constraints that shape the data model.** All relationships must be optional at the stored level (hence `Budget.expenses: [ExpenseItem]?` with the `expenseItems` computed wrapper). Enums are stored as `String` raw values. Fields can never be deleted from deployed CloudKit record types. These constraints affect every schema change.

5. **Navigation is centralized in a small `Router` class.** Push destinations go through `AppRoute`; sheets go through `SheetRoute`. Both are set via `@Environment(Router.self)` from any view. The `Router` is simple but has no coordination -- any view can set `router.sheet` at any time.

---

## 2. Architectural Patterns in Use

| Pattern | Where Applied | Key Files |
|---------|--------------|-----------|
| **View + Services (default)** | `BudgetsView`, `BudgetDetailView`, `SettingsView` | Views read via `@Query` / model relationships; write through `@Environment(\.modelContext)`; delegate math to `Domain/` services |
| **`@Observable` ViewModel (escalated)** | `AddEditBudgetView`, `AddEditExpenseView` | VM holds draft state; view owns VM as `@State`; VM never stores `ModelContext` -- receives it per call |
| **Pure domain services** | `PeriodCalculator`, `BudgetCalculator` | `enum` namespaces with `static` methods; no SwiftData, no SwiftUI; accept injected `Calendar` for testability |
| **Orchestrator service** | `BudgetLifecycleService` | Bridges pure calculator output to SwiftData writes; sole entry point for carry-over lifecycle |
| **Environment-based DI** | App-wide | `Router`, `AppSettings`, `SyncStatus` injected as `@Observable` via `.environment()`; `analytics` via custom `@Entry` on `EnvironmentValues` |
| **Protocol seam for testability** | `KeyValueStore`, `AnalyticsClient` | `MockKeyValueStore` and `SpyAnalyticsClient` in tests |
| **Value-based routing** | Navigation | `AppRoute` (push), `SheetRoute` (sheets) -- `Hashable` enums holding model references |
| **iCloud KV store for settings** | `AppSettings` | `NSUbiquitousKeyValueStore` with `KeyValueStore` protocol abstraction; syncs across devices |
| **CloudKit-first with local fallback** | Container creation | `makeProductionModelContainer` tries `.automatic`, falls back to `.none` |
| **Versioned schema** | `SchemaV1`, `BudgetMigrationPlan` | Single schema version; empty migration stages; ready for `SchemaV2` when needed |

---

## 3. Per-Dimension Findings

### 3.1 Layering and Separation of Concerns

**How it works:**

The source tree has clear layer folders:
- `Domain/` -- pure business logic (`PeriodCalculator`, `BudgetCalculator`, `BudgetLifecycleService`, `BudgetPeriod`, `ResetCadence`, `Weekday`).
- `Models/` -- SwiftData `@Model` types (`Budget`, `ExpenseItem`), schema, migration plan, extensions.
- `Views/` -- SwiftUI views, ViewModels, small UI components, modifiers.
- `Formatting/` -- `Decimal.formatted(currencyCode:display:)`, `CarryOverFormatter`, `OptionalDecimalFormatStyle`, `BudgetPeriod+Display`, `CurrencyDisplayPreference`.
- `Settings/` -- `AppSettings`, `KeyValueStore` protocol.
- `Sync/` -- `SyncStatus`.
- `Logging/` -- `AnalyticsClient` protocol, `ConsoleAnalyticsClient`, `AppLoggers`, `AnalyticsEnvironment`.

**Strengths / Preserve:**

- `PeriodCalculator` and `BudgetCalculator` are genuinely pure: no SwiftUI imports, no SwiftData imports. They accept injected `Calendar` and return value types. This is the gold standard for new domain logic.
- `BudgetLifecycleService` cleanly separates the "what to compute" (delegated to `BudgetCalculator`) from the "where to write" (SwiftData `ModelContext`). Its `refreshAndSave` returns a display-ready `BudgetLifecycleResult` struct, so callers never need to understand the roll/reset internals.
- ViewModels are thin: they hold draft state and validation, not fetching or observation logic. `ModelContext` is passed per-call, never stored. This avoids lifecycle traps.

**Pitfalls / Avoid:**

- `BudgetLifecycleService` accepts `AppSettings` directly (a concrete `@Observable` class). It only reads `weekStartDay` from it. If more settings influence lifecycle logic in the future, this coupling will grow. For now it is acceptable because `AppSettings` is testable via `MockKeyValueStore`, but be aware this is not a protocol boundary.
- `BudgetDetailView` contains `resetCarryOver()`, `resetBudget()`, and `deleteExpense()` as imperative methods that perform multi-step SwiftData writes (delete items, zero fields, bump timestamps, save). The tech-design-doc argues these do not meet ViewModel escalation triggers. This is defensible for now, but if any of these methods grow (e.g., adding analytics, undo support, or validation), they should be extracted. New destructive operations of similar complexity should follow this same pattern or escalate to a service method.
- ViewModels live in `Views/` (one as a separate file `AddEditBudgetViewModel.swift`, one inline in `AddEditExpenseView.swift`). This inconsistency is cosmetic but can confuse agents looking for ViewModels. There is no `ViewModels/` folder.
- `Formatting/` is cohesive: all files relate to rendering monetary or period values for display. The `CurrencyDisplayPreference` enum is both a formatting concept and a settings concept (it is stored in `NSUbiquitousKeyValueStore`). This dual role is fine given the app's size.

**Open Questions:**

- Should `BudgetLifecycleService.refreshAndSave` accept a `Weekday` directly instead of `AppSettings`, to narrow its dependency? This would be a minor refactor but would make the service fully decoupled from the settings layer.
- When the detail view's destructive actions grow beyond 3-4 lines of imperative code, at what point should they move to a service or ViewModel? The current threshold is subjective -- flag for discussion if a new destructive action requires cross-field validation or side effects beyond a single `context.save()`.

---

### 3.2 State Management Consistency

**How it works:**

- **List level:** `BudgetsView` uses `@Query(sort: \Budget.sortOrder)` for the budget list. SwiftData drives reactivity.
- **Row level:** Each `BudgetRowView` holds `@State private var lifecycle: BudgetLifecycleResult?`, populated by calling `BudgetLifecycleService.refreshAndSave`. This is re-triggered on `.task(id:)`, `scenePhase == .active`, and `onChange(of: budget.expenseItems.count)`.
- **Detail level:** `BudgetDetailView` follows the same pattern as `BudgetRowView` -- its own `@State var lifecycle`.
- **App root:** `simple_recurring_budgetsApp` owns `AppSettings`, `Router`, and `SyncStatus` as `@State private var` and injects them via `.environment()`.

**Strengths / Preserve:**

- The `@Query` + lifecycle result pattern is intentional: `@Query` provides the reactive list, while `BudgetLifecycleResult` provides computed display values (remaining, carry-over, period bounds) that depend on the current date and are too expensive or complex to derive in `body`. This is not a bug -- it is the designed data flow.
- Environment injection of `Router`, `AppSettings`, `SyncStatus`, and `analytics` is appropriate for this app size (4 items). SwiftUI's `@Environment` with `@Observable` types is the modern recommended pattern.
- `@State` on `@Observable` reference types in the App struct follows Apple's recommended pattern for app-scoped state that must survive view re-creation. This is correct.

**Pitfalls / Avoid:**

- The `lifecycle` result can be stale relative to the SwiftData model. For example, if CloudKit merges new expense items, `@Query` will update the list, but `lifecycle` will not refresh until one of the three triggers fires. In practice, `onChange(of: budget.expenseItems.count)` covers the most common case (new/deleted expenses), but a CloudKit merge that only changes an expense amount (not count) would leave `lifecycle.remaining` stale until the user backgrounds and foregrounds the app.
- When adding a new screen that displays budget lifecycle data (remaining, carry-over), always wire up the same three refresh triggers: `.task(id: budget.persistentModelID)`, `onChange(of: scenePhase)`, and `onChange(of: budget.expenseItems.count)`. Omitting one creates a staleness risk.
- `lifecycle` starts as `nil`. Views use `lifecycle?.remaining ?? 0` as a fallback. This means the first frame before `.task` runs shows zero remaining. For a list row this is briefly visible; for a detail screen it could flash. Be aware of this transient state if adding animations or transitions.

**Open Questions:**

- Should there be a centralized mechanism (e.g., a publisher or notification) that triggers lifecycle refresh on CloudKit merge events, rather than relying on the indirect `expenseItems.count` change? This would close the staleness gap for amount-only edits from another device.

---

### 3.3 Navigation Architecture

**How it works:**

- `Router` (`App/Router.swift`) is an `@Observable @MainActor final class` with two properties: `path: [AppRoute]` and `sheet: SheetRoute?`.
- `RootView` owns the `NavigationStack(path: $router.path)` and `.sheet(item: $router.sheet)`.
- Push destinations: `AppRoute.budgetDetail(Budget)`, `AppRoute.expenseDetail(ExpenseItem)`.
- Sheet destinations: `SheetRoute.addBudget`, `.editBudget(Budget)`, `.addExpense(Budget)`, `.settings`.
- Any view can write to `router.path` or `router.sheet` via `@Environment(Router.self)`.

**Strengths / Preserve:**

- The split between push (`AppRoute`) and sheet (`SheetRoute`) is principled: pushes are drill-down navigation (list -> detail -> expense); sheets are creation/editing modals. This matches Apple HIG and the UX brief.
- The Router is minimal (21 lines). It does not over-engineer navigation for a 5-screen app.
- `SheetRoute` conforms to `Identifiable` (via `id: Self`), enabling clean `.sheet(item:)` binding.

**Pitfalls / Avoid:**

- Route enums hold direct object references (`Budget`, `ExpenseItem`), not stable identifiers. This means they are not serializable for deep links, URL schemes, or widget intents. If deep linking becomes a requirement, routes will need to change to hold `PersistentIdentifier` or UUID and resolve objects at the destination.
- `AddEditBudgetView` wraps itself in its own `NavigationStack` (line 15 of `AddEditBudgetView.swift`), while `AddEditExpenseView` in sheet mode gets wrapped by `RootView`. `SettingsView` also wraps itself in a `NavigationStack`. This is not inconsistent -- each sheet that needs a toolbar must have a `NavigationStack`. But be aware: adding a new sheet that needs Cancel/Save toolbar buttons requires wrapping it in `NavigationStack` either at the sheet site in `RootView` or inside the view itself.
- There is no guard against setting `router.sheet` while another sheet is already presented. SwiftUI's `.sheet(item:)` handles this by dismissing the old sheet and presenting the new one, but this could cause unexpected dismissals if two views race to present. In practice this is unlikely given the app's simple flow.

**Open Questions:**

- Should the router expose methods (`presentSheet(_:)`, `push(_:)`) rather than raw property writes, to add future coordination (analytics, guards)? This is not needed today but could become valuable if navigation grows.

---

### 3.4 Data Model Design

**How it works:**

Two `@Model` types in `SchemaV1`: `Budget` (parent) and `ExpenseItem` (child). One-to-many relationship with cascade delete. String-backed enums for `period` and `resetCadence`. All monetary values use `Decimal`.

**Strengths / Preserve:**

- `Decimal` for all monetary values (never `Double`). This is correct and must be maintained.
- The `expenseItems` computed property (`expenses ?? []`) is the canonical accessor -- all app code uses it, never the raw `expenses`. This pattern must be followed for any new optional-relationship properties.
- `Budget.nextSortOrder(for:)` uses a fetch descriptor with limit 1 and reverse sort, which is efficient.
- `ExpenseItem.amount` is signed by convention (positive = expense, negative = add-funds). Computed properties `isAddFunds` and `displayAmount` provide the display abstraction. This design is already in place for F-6.01.

**Pitfalls / Avoid:**

- **String-backed enums:** `Budget.period` and `Budget.resetCadence` are stored as `String` and parsed with `BudgetPeriod(rawValue:)` at every read site. If a raw value is corrupted or unrecognized, views default to `.daily` and `BudgetLifecycleService` returns a fallback result. This is resilient but means a bug in enum naming could silently change a budget's behavior. When adding new enum cases, ensure the `rawValue` string is stable and never conflicts with existing values.
- **The `expenseItems` setter is dangerous.** The setter on `expenseItems` does `expenses = newValue`, which replaces the entire relationship collection. The inline comment warns this can "detach or remove linked `ExpenseItem`s." Do not use the setter unless you intend to replace the entire set. Prefer mutating individual items or setting `expense.budget = budget`.
- **`sortOrder` is a dense integer.** Reordering rewrites `sortOrder` on every `Budget` that moved (O(n) writes, single `context.save()`). For a personal budgeting app with <50 budgets, this is fine. If the budget count grows significantly, consider gap-based or fractional sort keys to reduce write amplification and CloudKit sync traffic.
- **No `@Attribute(.unique)` on `id`.** `Budget.id` and `ExpenseItem.id` are `UUID` with default `UUID()`. CloudKit does not enforce uniqueness constraints server-side. UUID collision is astronomically unlikely, but if you ever need server-side uniqueness guarantees, this is not available.
- **Carry-over state is persisted, not recomputed.** `carryOverAmount`, `carryOverLastProcessedDate`, and `carryOverLastResetDate` are stored on `Budget` and mutated by `BudgetLifecycleService`. This is a deliberate choice: recomputing carry-over from scratch would require iterating all historical expenses across all past periods, which is expensive and requires knowing the exact creation date and every period boundary. The trade-off is that these fields can become stale or inconsistent if the app crashes mid-save. The `try?` on `context.save()` exacerbates this risk.

**Open Questions:**

- The string-backed enum rationale (tech-design-doc) cites "human-readable CloudKit records." In practice, SwiftData's CloudKit integration stores these as `CKRecord` string fields, which are readable in CloudKit Dashboard. This justification holds but should be weighed against the parse-failure risk if an alternative (like `Int`-backed enums) would be more robust. Flag this if considering a schema migration.

---

### 3.5 Persistence and Sync

**How it works:**

- Container creation: `makeProductionModelContainer` tries `cloudKitDatabase: .automatic` first. If `ModelContainer` init throws (e.g., no iCloud account on Simulator), it falls back to `cloudKitDatabase: .none` (local disk). If both fail, `fatalError`.
- All writes use `try? context.save()` -- errors are silently discarded.
- `SyncStatus` tracks whether the container is CloudKit-backed or local-fallback. `SettingsView` queries `CKContainer.accountStatus()` asynchronously and observes `CKAccountChanged` / `NSUbiquityIdentityDidChange` notifications.

**Strengths / Preserve:**

- The CloudKit-first-with-fallback pattern is correct for this app. SwiftData handles the complexity of CloudKit record mapping.
- `SyncStatus` clearly separates launch-time container state (`containerBacking`, immutable) from runtime account state (`accountStatus`, mutable). The derived `rowState` is a clean four-state enum for the UI.
- In-memory containers for tests and previews (`TestModelContainer`, `InMemoryModelContainer`) with `cloudKitDatabase: .none` ensure isolation.

**Pitfalls / Avoid:**

- **Silent save failures are the highest-risk pattern in this codebase.** There are 10 `try? context.save()` sites in production code (excluding `DebugData` and `BudgetDetailFixtures`). If a save fails:
  - The user sees the in-memory change (e.g., expense appears deleted) but it is not persisted. On next launch, the "deleted" expense reappears.
  - `BudgetLifecycleService` may have updated carry-over fields in memory but failed to persist them, leading to double-rolling on next launch.
  - There is no logging, toast, or analytics event for save failures.
  - **When adding new write paths, be aware this is the established pattern. Do not assume saves succeed. If you need guaranteed persistence (e.g., for a destructive operation), consider adding error handling or at minimum logging the failure.**
- **Specific `try?` sites in production code:**
  - `BudgetLifecycleService.refreshAndSave` (line 115)
  - `AddEditBudgetViewModel.save` (lines 91, 117), `.delete` (line 68)
  - `AddEditExpenseViewModel.save` (lines 57, 77), `.delete` (line 85)
  - `BudgetDetailView.resetCarryOver` (line 260), `.resetBudget` (line 272)
  - `BudgetDetailView+ExpenseSection.deleteExpense` (line 84)
  - `BudgetsView.move` (line 130)
  - `simple_recurring_budgetsApp.deleteAllBudgets` (line 145, DEBUG only)
- **~~`fatalError` on container creation.~~** **Resolved** by the `container-creation-recovery` change (issue #132, 2026-05-28). `makeProductionModelContainer` now `throws`, `AppStartup` owns the result, and the `@main` body presents `ContainerFailureView` (Retry + Send Feedback) instead of crashing when both creation paths fail.
- **CloudKit connectivity after launch.** Once the container is created with `cloudKitDatabase: .automatic`, SwiftData/CloudKit handles intermittent connectivity internally (queuing changes for sync). Data is not lost if connectivity drops. However, the `containerBacking` never changes from `.cloudKit` to `.localFallback` mid-session -- it reflects the container type chosen at launch.

**Open Questions:**

- Should a lightweight `do { try context.save() } catch { logger.error(...) }` wrapper be introduced as a standard practice? This would not change behavior but would provide diagnostic visibility into save failures. This is a low-effort, high-value improvement to consider.
- `BudgetMigrationPlan.stages` is empty. The first schema change must add a `SchemaV2` with `VersionedSchema` and an explicit `MigrationStage`. CloudKit's no-delete-field constraint means additive changes only. Test migration thoroughly before shipping.

---

### 3.6 Testability

**How it works:**

- Swift Testing (`import Testing`, `@Test`, `#expect`, `try #require`) for all tests. No XCTest in unit tests.
- `TestModelContainer.make()` creates an in-memory SwiftData container for test isolation.
- Domain tests (`BudgetCalculatorTests`, `PeriodCalculatorTests`) inject a fixed UTC `Calendar` for deterministic date math.
- ViewModel tests instantiate VMs directly, pass `MockKeyValueStore`-backed `AppSettings`, and call `save(context:)` / `delete(context:)` with test `ModelContext`.
- `BudgetDetailViewActionsTests` tests the algorithm of view-owned actions (resetBudget, resetCarryOver, deleteExpense) by inlining the same logic against a test `ModelContext` -- it does not instantiate the view.

**Strengths / Preserve:**

- Domain layer testability is excellent. `PeriodCalculator` and `BudgetCalculator` are fully deterministic with injected `Calendar`. New domain logic should follow this pattern.
- `KeyValueStore` protocol with `MockKeyValueStore` is a clean test seam. `AppSettings` is fully testable without touching real iCloud KV store.
- `SpyAnalyticsClient` captures events for assertion. Use it when testing code that should emit analytics.
- Test files mirror the source folder structure (`Domain/`, `Models/`, `Views/`, `Formatting/`, `Settings/`, `Sync/`, `Logging/`). Follow this convention.

**Pitfalls / Avoid:**

- **ViewModel tests are integration tests**, not unit tests. They require a `ModelContainer` + `ModelContext` because `save(context:)` and `delete(context:)` operate on real SwiftData. This is acceptable given the VM's role (it is a thin persistence coordinator), but be aware the tests are slower than pure unit tests.
- **View-owned actions are tested by algorithm duplication.** `BudgetDetailViewActionsTests` does not call `BudgetDetailView.resetBudget()` -- it replicates the same steps against a `ModelContext`. This means the tests verify the algorithm but not the view's actual call to it. If the view's method diverges from the test, the test will not catch it. When modifying `resetBudget()`, `resetCarryOver()`, or `deleteExpense()`, update the corresponding test to match.
- **`BudgetLifecycleService` tests hit SwiftData** because the service writes to `ModelContext`. This is by design (it is the persistence bridge), but these tests are slower than the pure calculator tests.
- **No snapshot or UI tests are active.** The `simple-recurring-budgetsUITests/` folder contains only Xcode-template stubs. Visual regressions are not caught by automated tests.

**Open Questions:**

- If view-owned destructive actions grow in complexity, should they be extracted to a testable function (e.g., a static method on a service or extension) that both the view and the test call? This would eliminate the algorithm-duplication risk.

---

### 3.7 Error Handling and Resilience

**How it works:**

- Persistence: all saves use `try?` (see section 3.5 for full enumeration).
- Enum parsing: `BudgetPeriod(rawValue:)` and `ResetCadence(rawValue:)` failures are handled differently depending on context:
  - In views (`BudgetRowView.period`, `BudgetDetailView.period`): fallback to `.daily`.
  - In `BudgetLifecycleService.refreshAndSave`: a `guard` returns a fallback `BudgetLifecycleResult` using `.daily` period boundaries without mutating the budget.
- Container creation: `fatalError` if both CloudKit and local fail.
- `OptionalDecimalFormatStyle.parse`: throws `CocoaError(.formatting)` for invalid input; SwiftUI's `TextField` handles this by reverting the field.

**Strengths / Preserve:**

- The `guard` fallback in `BudgetLifecycleService` is defensive: it avoids writing corrupted carry-over values back to the model. This is the right behavior for a service that might encounter malformed data from a CloudKit sync.
- `OptionalDecimalFormatStyle` correctly maps empty input to `nil` rather than zero, enabling the "Save disabled until amount entered" UX.

**Pitfalls / Avoid:**

- **Inconsistent enum fallbacks.** Views default to `.daily` on parse failure, which silently changes the displayed period for a corrupted budget. `BudgetLifecycleService` also defaults to `.daily` in its fallback path. This means a corrupted `period` string will be displayed as "Daily" everywhere without any user indication that something is wrong. If you encounter enum parsing in new code, prefer logging the failure.
- **No user-facing error state.** There is no generic error banner, toast, or alert mechanism. If a write fails, the user sees stale data with no indication. Adding a lightweight error surface (even just a logged `OSLog.error`) would improve debuggability.
- **`fatalError` is unrecoverable.** In `makeProductionModelContainer`, if the local-only container also fails to create, the app crashes. In practice this requires a corrupted SQLite database or a permissions issue -- extremely unlikely on a real device, but a crash is a bad user experience. There is no path to "show an error screen and let the user retry."

**Open Questions:**

- Should the app log (via `OSLog.error`) every `try?` save failure, even if it does not surface an error to the user? This would at least provide diagnostic breadcrumbs in Console.app.

---

### 3.8 Concurrency Model

**How it works:**

- `Router` and both ViewModels are `@MainActor`.
- `AppSettings` is `@Observable` but not `@MainActor`-annotated. However, it registers a `NotificationCenter` observer on `.main` queue and uses `MainActor.assumeIsolated` in the callback and in `deinit`.
- `BudgetLifecycleService` is an `enum` with static methods and no actor annotation. It is always called from view `body` or `.task` contexts (which are `@MainActor` in SwiftUI), so in practice it runs on the main actor.
- `SettingsView` uses `async` for `CKContainer.accountStatus()` and `NotificationCenter.default.notifications(named:)` streams.
- No Combine usage anywhere.

**Strengths / Preserve:**

- `@MainActor` on `Router` and ViewModels is correct. SwiftUI view state must be main-actor-isolated.
- The `SettingsView` async pattern (`task { await loadICloudStatus() }` + `task { await observeAccountChanges() }`) using `withTaskGroup` for parallel notification observation is well-structured.

**Pitfalls / Avoid:**

- **`BudgetLifecycleService` has an implicit main-actor assumption.** It writes to `ModelContext` (which in SwiftUI is main-actor-isolated via `@Environment(\.modelContext)`), but it has no `@MainActor` annotation. This works because callers always invoke it from the main actor. If someone calls it from a background context (e.g., a `ModelActor`), they will get a data race or a SwiftData error. New callers of `BudgetLifecycleService` must be on the main actor.
- **`AppSettings.deinit` uses `MainActor.assumeIsolated`.** The comment explains this is safe because `AppSettings` is always owned by `@MainActor` code and deallocated on the main thread. This is a known Swift 6 pain point (`deinit` is `nonisolated`). Do not copy this pattern unless the same ownership invariant holds.
- **`refreshLifecycle()` is synchronous on the main thread.** `BudgetLifecycleService.refreshAndSave` does date math, expense filtering, and a `context.save()` synchronously. For a budget with hundreds of expenses spanning many periods, this could cause a visible hitch. The tech-design-doc section 6 mentions "Background Over/Under roll" but this is not implemented. For now, this is acceptable for the expected data volume.
- **`MainActor.assumeIsolated` in `NotificationCenter` callback** (`AppSettings` init): The observer is registered on `.main` queue, so the callback is guaranteed to be on the main thread. `MainActor.assumeIsolated` makes this explicit to the compiler. This is correct but brittle -- if the queue parameter were changed, the assumption would break silently at runtime.

**Open Questions:**

- Should `BudgetLifecycleService` be annotated `@MainActor` to make its threading requirement explicit? This would prevent accidental background calls but would also prevent future use from a `ModelActor` for background processing. Defer this decision until background processing is needed.

---

### 3.9 Extensibility and Future Readiness

**How it works:**

The data model and architecture have provisions for several planned features. The tech-design-doc section 9 lists future technical surfaces.

**Strengths / Preserve:**

- **F-6.01 (Adding funds):** The data model is ready. `ExpenseItem.amount` is signed; `isAddFunds` and `displayAmount` computed properties exist. `BudgetCalculator.remaining` correctly handles negative amounts (they reduce the expense total). Only the UI for creating an add-funds entry is missing.
- **F-4.01-02 (Themes):** The `appBackground()` modifier and named color assets (`AppBackground`, `CellBackground`) are a clean extension point. A theme engine would swap these asset values; the 30+ call sites of `.appBackground()` and `Color("CellBackground")` would not need to change.
- **F-6.02 (Expense Type):** `ExpenseItem.expenseType: String?` is already in the schema, stored but not surfaced in UI.
- **F-5.01 (Start of week):** `AppSettings.weekStartDay` is already stored, synced, and consumed by `PeriodCalculator` and `BudgetLifecycleService`. The Settings UI for changing it (with confirmation alert) is implemented.
- **Paused features (Reset Cadences):** `ResetCadence` enum, `Budget.resetCadence` field, `BudgetCalculator.checkScheduledReset`, and `BudgetLifecycleService` integration are all implemented and tested. They are gated by comments and the `.never` default, not by `#if` flags. Unpausing requires surfacing the UI and changing the default in `Budget.init`.

**Pitfalls / Avoid:**

- **macOS / iPad split view is not implemented.** PRD section 6.1 lists macOS as a target. The UX brief says "On iPad and macOS, prefer a two-column split view." The current code uses `NavigationStack` only -- no `NavigationSplitView`. Adding multi-column support will require reworking `RootView` and potentially the `Router` (which assumes a single path). Do not assume the current navigation architecture scales to multi-column without changes.
- **AI features (F-7.01-03) will require async coordination.** Receipt scanning (Vision), speech recognition (`SFSpeechRecognizer`), and voice queries all involve async framework calls. Per the escalation criteria, these screens will need ViewModels. There is no existing pattern for managing async task lifecycle in a ViewModel -- each feature will need to design its own. Consider establishing a pattern (e.g., a `@Published`-like loading state enum) before implementing the first one.
- **No App Intents or Shortcuts support.** F-7.02-03 mention Siri. The app has no `AppIntents` framework integration. This is a substantial addition that requires exposing model queries and actions as intents.

**Open Questions:**

- For macOS: should `RootView` conditionally use `NavigationSplitView` on iPad/Mac and `NavigationStack` on iPhone, or should the architecture adopt `NavigationSplitView` universally (collapsing to stack on iPhone)? This is an architectural decision that should be made before implementation, not during.
- For AI features: should a shared async task management pattern (e.g., a base ViewModel protocol with loading/error state) be established upfront, or should each feature design its own? The current codebase has no precedent for this.

---

### 3.10 Code Organization and Developer Experience

**How it works:**

Source folders: `App/` (4 files), `Domain/` (6), `Formatting/` (4), `Logging/` (4), `Models/` (6), `Previews/` (3), `Settings/` (2), `Sync/` (1), `Views/` (13). Test folders mirror source structure. Xcode uses `PBXFileSystemSynchronizedRootGroup` (filesystem-synced groups), so adding a file to the folder automatically includes it in the target.

**Strengths / Preserve:**

- **Filesystem-synced Xcode groups** eliminate the "file exists but is not in the target" class of bugs. New files in the source folder are automatically compiled.
- **Test structure mirrors source structure.** `Domain/BudgetCalculatorTests.swift` tests `Domain/BudgetCalculator.swift`. Follow this convention.
- **`#if DEBUG` gating** on `DebugData`, launch modes, preview containers, and delete-all is consistent. Debug code never ships in release builds.
- **Localization is thorough.** Every user-facing string uses `String(localized:defaultValue:comment:)` with a translator context comment. The `comment:` is not optional when the string could be ambiguous. The pattern for count-driven plurals (CLDR buckets via String Catalog) and inline vs. list-label period names (separate keys, not `.lowercased()`) is documented and correct.
- **Previews are comprehensive.** Most views have light mode, dark mode, accessibility size, and edge-case previews (empty state, over budget, carry-over disabled).

**Pitfalls / Avoid:**

- **`Views/` is the largest folder (13 files)** and contains heterogeneous content: full screens (`BudgetsView`, `BudgetDetailView`, `SettingsView`), form screens (`AddEditBudgetView`, `AddEditExpenseView`), ViewModels (`AddEditBudgetViewModel`, inline `AddEditExpenseViewModel`), small components (`CarryOverChip`, `RemainingBar`, `CurrencyPickerView`), extensions (`Color+Money`), and modifiers (`View+AppBackground`). At 13 files this is manageable, but as screens are added, consider grouping by feature (e.g., `Views/Budget/`, `Views/Expense/`, `Views/Settings/`).
- **ViewModel file placement is inconsistent.** `AddEditBudgetViewModel` is a separate file; `AddEditExpenseViewModel` is defined at the top of `AddEditExpenseView.swift`. Both patterns work, but an agent searching for "all ViewModels" will miss the inline one. For new ViewModels, prefer a separate file to match the `AddEditBudgetViewModel` precedent.
- **Localization verbosity.** The `String(localized:defaultValue:comment:)` pattern adds 3-5 lines per string. This is correct for i18n but makes views long. Do not attempt to "simplify" this by dropping `defaultValue:` or `comment:` -- they are required by the localization strategy. The `defaultValue` is the English fallback; the `comment` is translator context.

**Open Questions:**

- At what file count should `Views/` be split? A reasonable threshold might be 20+ files or when two features have 3+ views each. This is not urgent at 13 files.

---

## 4. Priority-Ranked Concerns

Ordered by risk (impact times likelihood). These are observations, not action items -- flag them when they become relevant to your work.

| # | Concern | Risk | Dimension |
|---|---------|------|-----------|
| 1 | **Silent save failures (`try?` on all `context.save()`)** | Data loss or inconsistency if a save fails; no diagnostic visibility | 3.5, 3.7 |
| 2 | **Lifecycle result staleness after CloudKit merge** | User sees incorrect remaining/carry-over until a refresh trigger fires (e.g., CloudKit merges an amount change but not a count change) | 3.2 |
| 3 | **`BudgetLifecycleService` implicit main-actor assumption** | Data race if called from background context; no compile-time enforcement | 3.8 |
| 4 | **No user-facing error surface** | User cannot distinguish "operation succeeded" from "operation silently failed" | 3.7 |
| 5 | ~~**`fatalError` on container creation failure**~~ — resolved by `container-creation-recovery` (#132, 2026-05-28) | App crashes with no recovery if both CloudKit and local container fail (extremely unlikely on real device) | 3.5, 3.7 |
| 6 | **View-owned destructive actions tested by algorithm duplication** | Test and view code can diverge silently; test verifies algorithm, not the actual call path | 3.6 |
| 7 | **No `NavigationSplitView` for iPad/Mac** | PRD and UX brief specify multi-column layout; current code is `NavigationStack` only | 3.9 |
| 8 | **Dense `sortOrder` rewrites on reorder** | O(n) writes and CloudKit syncs on every drag-to-reorder; acceptable for <50 budgets | 3.4 |
| 9 | **Route enums hold object references, not stable identifiers** | Deep linking / widget intents cannot serialize current routes | 3.3 |
| 10 | **No async coordination pattern for future AI features** | Each feature (Vision, Speech, Intents) will need to design its own async lifecycle | 3.9 |
