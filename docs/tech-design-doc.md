# Technical Design Document

| Field              | Value                          |
| ------------------ | ------------------------------ |
| **Version**        | 0.10                           |
| **Last Updated**   | 2026-04-29                     |
| **Author / Owner** | Jimmy Ho                       |

> Master technical reference for the Simple Recurring Budgets app. Complements [main-prd.md](main-prd.md) (product source of truth) and [product-features-planning.md](product-features-planning.md) (feature backlog). Intended as durable context for both human and agentic development.

---

## 1. System Overview

A native Apple-platform app (iOS, iPadOS, macOS) that helps users track spending against simple recurring budgets. There is no app-owned backend; all data lives on-device via SwiftData and syncs across the user's devices through CloudKit.

### 1.1 Key Technical Constraints (from PRD)

- Latest stable Swift and latest major OS releases only.
- SwiftData for persistence; CloudKit for cross-device sync.
- No app-owned server infrastructure.
- Apple-first dependency policy; minimize third-party libraries.
- Monetary values stored as `Decimal`, never floating-point.
- Currency is per-Budget, not a global app setting.

---

## 2. Architecture

### 2.1 Pattern: View + Services, ViewModels on demand

**Default:** Screens are SwiftUI Views that read data with `@Query`, write through `@Environment(\.modelContext)`, and delegate non-trivial logic to pure domain services in `Domain/` (`BudgetLifecycleService`, `BudgetCalculator`, `PeriodCalculator`). No companion ViewModel is introduced by default.

**Why not a VM on every screen.** The `Domain/` layer already carries the testable business logic as pure, SwiftData-free services (see §5.4). Adding a VM to thin list or detail screens mostly relays calls, duplicates state, and introduces lifecycle plumbing (`ModelContext` injection, `bind` timing, preview setup) without a payoff. Keeping reads in the view via `@Query` also preserves SwiftUI's automatic invalidation on SwiftData changes — something a VM-held fetch would have to reimplement.

**Escalate to an `@Observable` ViewModel only when at least one of these is true:**

1. The screen holds **non-trivial draft/form state** not persisted until the user commits (e.g., an Add/Edit screen with cross-field validation such as Budget Period → Reset Cadence rules per [PRD §6.7](main-prd.md#67-carry-over-behavior)). _(Note: Budget Period → Reset Cadence cross-field validation is **PAUSED** — Reset Cadences are not in scope; do not implement this validation in UI while paused.)_
2. The screen owns **`async` / `Task` work** or concurrency-scoped state (e.g., future F-7.01 receipt OCR via Vision, F-7.02 speech recognition).
3. The screen needs **a multi-step user action** chaining validation, multiple writes, and side effects beyond a one-liner.
4. The screen has **derived display state expensive to recompute** inside `body` that benefits from caching outside it.

**When a VM is escalated, these rules apply:**

- Name and shape: `@Observable final class <Screen>ViewModel`, owned by the view via `@State`.
- VM holds **draft state and pure logic only**. It does **not** store `ModelContext`, does **not** hold `@Query` results, and does **not** fetch.
- Methods that need to write take `(context: ModelContext, ...)` at the call site (and `AppSettings` similarly when relevant). This avoids any `init(context:)` / `bind(context:)` lifecycle trap — `@Environment(\.modelContext)` is only readable inside `body`, and passing it per call keeps Sendable/ownership concerns simple.
- Reads stay in the view via `@Query`. The VM never fetches.

**Grey-area protocol — ask before scaffolding a VM.** A VM is harder to remove than to add. If a screen is on the fence, the implementer must ask the user for an explicit judgment call **before** creating a VM file. Explicit grey-area triggers that require a ping:

- More than 3 mutable form fields.
- A framework call inside the screen (Vision, Speech, PhotosUI, SiriKit / App Intents, `SFSpeechRecognizer`, network).
- A single user input that mutates more than one model property or couples fields (e.g., changing Budget Period must re-validate Reset Cadence). _(Reset Cadence coupling is **PAUSED** — do not implement while paused.)_
- The screen is expected to grow materially within the next 1–2 features.

Pure display-only subviews (row cells, badges, amount formatters) remain logic-free regardless of which side of the rule the parent screen falls on.

**Implemented View + Services screens:**

- `BudgetsView` — root list; `@Query` drives the row list; `BudgetLifecycleService.refreshAndSave` called from each row's `.task(id:)` and `onChange(of: scenePhase)`.
- `BudgetDetailView` — Budget detail; lifecycle refresh invoked from the view body via `.task(id: budget.persistentModelID)`, `onChange(of: scenePhase)`, and `onChange(of: budget.expenseItems.count)`. Destructive actions (`resetBudget`, `resetCarryOver`, `deleteExpense`) are short imperative methods on the view that write through `@Environment(\.modelContext)` and call `BudgetLifecycleService` afterward. None of the §2.1 escalation triggers apply.

### 2.2 Navigation: `NavigationStack` with value-based routing

The app's information architecture is a simple stack: Budgets list → Budget detail → Expense detail. A `NavigationStack` with a `Hashable` route enum and `navigationDestination(for:)` handles this cleanly — type-safe, state-driven, and deep-linkable. iPad/Mac can use adaptive layout without requiring a full split view.

A small `@Observable Router` (`path: [AppRoute]`, `sheet: SheetRoute?`) is owned by the navigation host (`RootView`) as `@State` and exposed via `@Environment` so leaf screens trigger pushes and sheets without holding navigation state themselves.

---

## 3. Data Model

### 3.1 Approach

Two SwiftData `@Model` entities: **Budget** and **ExpenseItem**, linked by a one-to-many relationship (Budget → ExpenseItem, cascade delete). Supporting enums (`BudgetPeriod`, `ResetCadence`) are `String`-backed `Codable` types stored inline.

The user-facing entry point for deleting a `Budget` is the **Delete Budget** button on the Add/Edit Budget sheet (Edit mode only). Confirming the dialog calls `context.delete(budget)` + `context.save()` on `AddEditBudgetViewModel`; the `@Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)` rule on `Budget` automatically removes the budget's `ExpenseItem` rows in the same save. No schema or CKRecord change is involved.

> [!NOTE]
> **PAUSED — Reset Cadences feature is not in scope.** `ResetCadence` and the `Budget.resetCadence` field are retained for schema stability and the future un-pause. All new Budgets persist `"never"`. Do not surface Reset Cadence in UI, plans, or new specs while paused; the type and engine are available for future use.

**CloudKit optional relationship pattern:** CloudKit requires all relationships to be optional (records may arrive out-of-order during sync). The stored `Budget.expenses` property is therefore typed `[ExpenseItem]?`. A non-optional computed property `expenseItems: [ExpenseItem]` (`get { expenses ?? [] }`, settable) is the canonical accessor for all app code, so no call site ever handles optionality. The raw `expenses` property should not be accessed outside of the model definition.

Key fields on Budget include allocation, period, currency code (ISO 4217), and Over/Under state (cumulative amount + last reset date + reset cadence). ExpenseItem carries amount, optional name, and date. All monetary values use `Decimal`. _(Reset cadence is stored but **PAUSED** — defaults to `"never"` for new records.)_

Derived values — **Remaining for current Budget Period** and **Over/Under display** — are computed at read-time, not persisted.

### 3.2 Over/Under Bookkeeping

Per [PRD §6.7](main-prd.md#67-overunder-carryover-behavior):

- **Period boundary roll**: When the app detects a new Budget Period has started, compute `allocation − expenses` for the completed period(s) and fold into the stored Over/Under amount. This happens eagerly on app launch / budget access.
- **Scheduled reset**: Compare last reset date against current date and the budget's reset cadence. If a reset boundary has passed, zero out Over/Under and update the last reset date. _(PAUSED — Reset Cadences feature is not in scope. The code path is retained and unit-tested, but all new Budgets default to `"never"`, so this is a no-op in practice. Do not surface scheduling configuration in UI or new specs while paused.)_
- **Manual reset**: User action zeros Over/Under and updates the last reset date.

### 3.3 Migration Strategy

SwiftData handles lightweight migrations automatically for additive changes. For breaking changes, use `VersionedSchema` and `SchemaMigrationPlan` with unit-tested migration steps. Always test CloudKit compatibility after schema changes — CloudKit cannot delete fields from deployed record types.

---

## 4. Persistence and Sync

### 4.1 SwiftData + CloudKit

SwiftData persistence with `cloudKitDatabase: .automatic` on `ModelConfiguration` enables CloudKit sync with the default container. This is the simplest integration path for SwiftData-backed CloudKit apps.

### 4.2 CloudKit Setup Requirements

- **iCloud container identifier**: Must be set in entitlements (currently empty — needs a value like `iCloud.com.jimmyho.simple-recurring-budgets`).
- **Capabilities**: iCloud (CloudKit) + Push Notifications (background remote-notification already in `Info.plist`).
- **Dashboard**: Register the container in CloudKit Dashboard; schema is auto-created from SwiftData models on first push.

### 4.3 CloudKit Constraints on Schema

CloudKit imposes rules that affect SwiftData model design:

- All properties must be optional at the CKRecord level (SwiftData handles this, but be aware during manual CKRecord work).
- No unique constraints enforced server-side — `@Attribute(.unique)` is local-only. UUID-based IDs provide practical uniqueness.
- Relationships are modeled via CKReference; only one-to-many with a parent reference is well-supported.
- Fields cannot be deleted from CKRecord types once deployed — only add.
- Default values must be set in code, not relied upon from CloudKit.

### 4.4 Conflict Resolution

SwiftData + CloudKit uses last-writer-wins at the record level by default. For this app's use case (single user across personal devices), this is acceptable.

### 4.5 App Settings (NSUbiquitousKeyValueStore)

Lightweight app-wide preferences (e.g., default carry-over toggle, start-of-week day) use `NSUbiquitousKeyValueStore` instead of `UserDefaults`. This gives automatic iCloud sync across the user's devices signed into the same Apple ID — settings configured on one device appear on all others without requiring SwiftData or a custom sync mechanism. The iCloud key-value store shares the app's existing iCloud container entitlement (same as CloudKit).

Key constraints:
- 1 MB total / 1024 keys maximum — suitable for a small number of preferences.
- Eventual consistency — changes propagate when connectivity is available; the local value is authoritative until sync arrives.
- `NSUbiquitousKeyValueStore.didChangeExternallyNotification` must be observed to update in-memory state when another device writes.
- No `register(defaults:)` equivalent — code must check for key existence and apply hard-coded defaults on first read.
- Testability via a `KeyValueStore` protocol seam (since `NSUbiquitousKeyValueStore` cannot be instantiated with a custom suite).

**Keys in use:**

| Key | Type | Owner | Purpose |
|-----|------|-------|---------|
| `"defaultCarryOverEnabled"` | `Bool` | `AppSettings` | Default carry-over toggle for new budgets |
| `"weekStartDay"` | `Int64` (`Weekday.rawValue`) | `AppSettings` | First day of the week (locale default if absent) |
| `"currencyDisplay"` | `String` (`CurrencyDisplayPreference.rawValue`) | `AppSettings` | Currency display format for monetary amounts (symbol / code / codeAndSymbol); default `.symbol` |

> **Orphaned key:** The string `"seededV1"` was used by a prior first-run seeder (removed in change `remove-first-run-seeder`) and is now a harmless leftover on upgraded installs. It SHALL NOT be reused as a new KV key; the `"V1"` suffix remains reserved per convention so any future one-time-reseed change introduces a distinct key name (e.g., `"seededV2"`).

**SyncStatus environment value:** `SyncStatus` is an `@Observable final class` injected into the SwiftUI environment via `.environment(syncStatus)` in `simple_recurring_budgetsApp`. It carries two properties: `containerBacking: ContainerBacking` (`.cloudKit` or `.localFallback`), which is determined once at launch from the outcome of `makeProductionModelContainer` and never mutated; and `accountStatus: AccountStatus` (`.checking`, `.available`, or `.unavailable`), which is updated asynchronously by `SettingsView` via `CKContainer.default().accountStatus()` and live `CKAccountChanged` / `NSUbiquityIdentityDidChange` notification observers. A derived `rowState: RowState` property combines both fields to produce the four-state view-state for the Settings iCloud row (`.checking`, `.available`, `.paused`, `.unavailable`). Screens consume it via `@Environment(SyncStatus.self) private var syncStatus`.

---

## 5. Internationalization, Accessibility, and Testing

### 5.1 Internationalization

All user-facing text uses Xcode **String Catalogs** and `LocalizedStringKey` — no hard-coded English in production views. Dates and numbers use Foundation format styles that auto-adapt to locale. Each Budget stores its own ISO 4217 currency code; formatting uses `Decimal.FormatStyle.Currency`.

The canonical catalog lives at `simple-recurring-budgets/Resources/Localizable.xcstrings` and is picked up automatically by the app target's `PBXFileSystemSynchronizedRootGroup`; no `project.pbxproj` changes are needed when adding or renaming strings. Every new user-facing string in a production view must use `Text("key", comment: "translator context")` or `LocalizedStringKey("key")`. The `comment:` argument is required whenever the source string would be ambiguous out of context (short labels, button titles, destructive action names, etc.). Placeholder strings in `Views/RootView.swift` are exempt until the real T-2 screens replace them.

**Count-driven plurals** — when copy genuinely varies by count (e.g. "1 item" vs "2 items"), use Xcode String Catalog plural variations (CLDR `one`/`other` per locale) rather than Swift-side word substitution. The Swift call site passes the integer count as an interpolation (`Text("my.key \(count)")`), which resolves to the catalog key `"my.key %lld"`; the catalog encodes locale-specific `one`/`other` (and `few`/`many` where needed) buckets. Prefer rewriting copy to avoid count-driven plurals when a count-free form ("all expenses", "all items") is equally clear — this keeps the catalog simpler and the call site free of runtime arguments.

**Inline vs list-label period names** — `BudgetPeriod.inlineLabel` (`period.daily.inline`, `period.weekly.inline`, `period.biweekly.inline`, `period.monthly.inline`) and `BudgetPeriod.listLabel` are backed by **separate** per-locale keys. Inline forms are **never** derived from list-label forms via `.lowercased()`, ensuring translators control case for each usage context independently.

### 5.2 Accessibility

- **Dynamic Type**: System text styles everywhere; no fixed frame heights that clip at larger sizes.
- **VoiceOver**: Meaningful accessibility labels on all interactive controls; financial amounts include currency context.
- **Dark Mode**: Semantic system colors and Asset Catalog color sets with light/dark variants; no hard-coded color literals.

### 5.3 Testing

**Swift Testing** for all new tests; XCTest for UI tests where needed. In-memory `ModelContainer` for all automated data tests to ensure isolation. Business logic (budget math, Over/Under rolls, date boundaries) lives in pure, testable services with minimal or no SwiftData/UI dependencies.

**Test Runs**: When supporting only iPhone and iPad, we only need to run the unit test suites for one iPhone model using the latest OS version available. For UI tests, run the tests for the appropriate platform for platform-specific tests, defaulting to iPhone when not specified. Again, unless tests are specifically testing different device models or OS versions, only one combination of one arbitrary device model + latest available OS version is necessary.

### 5.4 Budget Math Service Layer

Three services in `Domain/` implement all budget math and lifecycle orchestration with no SwiftUI dependencies:

- **`PeriodCalculator`** — Pure date-only math (no SwiftData): computes period start/end dates and enumerates period boundaries between two dates. All methods accept an injected `Calendar` for deterministic, timezone-safe results in tests.
- **`BudgetCalculator`** — Pure financial math (no SwiftData) built on `PeriodCalculator`: computes remaining for the current period, rolls carry-over across completed periods, and detects scheduled reset boundaries. Returns structured result types (`CarryOverRollResult`, `ResetCheckResult`) so callers have all the data they need to write back to the model.
- **`BudgetLifecycleService`** — The sole orchestrator that binds `BudgetCalculator` outputs to SwiftData. Takes a `Budget`, `AppSettings`, and `ModelContext`; runs the strict PRD §6.7 sequence (roll → persist → reset if needed → persist); and returns a `BudgetLifecycleResult` with `remaining`, `carryOverAmount`, `periodStart`, and `periodEnd` — everything a screen needs for display. Writes `carryOverAmount`, `carryOverLastProcessedDate`, `carryOverLastResetDate`, and `lastModified` back to the `Budget` in a single `context.save()`, and only when at least one field changed.

**Biweekly anchor:** For biweekly periods, the cycle anchor is derived from `createdAt` + `weekStart` at call time — no extra stored field is needed. Changing `weekStartDay` cascades to biweekly alignment (acknowledged by F-5.01).

**Caller consumption:** Screens call `BudgetLifecycleService.refreshAndSave(_:settings:context:)` eagerly on budget access (screen appearance and `scenePhase == .active`) and bind the returned `BudgetLifecycleResult` to the view. Per §2.1, simple screens invoke this directly from the view body / `.task` using `@Environment(\.modelContext)` and the injected `AppSettings`; screens that have escalated to a ViewModel expose a method taking `(settings: AppSettings, context: ModelContext, ...)` at the call site and forward to the service. Screens (and any VMs) do **not** call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly for the eager access flow — `BudgetLifecycleService` is the single entry point for that sequence.

### 5.5 Color Palette and Theming

The app uses a warm earth-tone palette defined as named color assets in `Resources/Assets.xcassets`, with separate light and dark appearances. All views must use these named assets — never hard-coded color literals.

#### Color assets

Exact values are defined in `Resources/Assets.xcassets` with separate light and dark appearances. The table below documents semantic intent only.

| Asset name | Semantic role |
|---|---|
| `AppBackground` | Screen/page background; fills behind nav bar, list, and empty states |
| `CellBackground` | List row background |
| `AccentColor` | Tint for interactive controls (buttons, chevrons, toggles) |

#### Applying to screens

**`View+AppBackground.swift`** exposes a single `appBackground()` modifier that every screen calls once on its root content view:

```swift
Group { ... }
    .navigationTitle("My Screen")
    .appBackground()
```

This modifier applies:
- `.background(Color("AppBackground").ignoresSafeArea())` — fills the full screen including safe areas; shows through the transparent nav bar while the large title is visible.
- `.toolbarBackground(Color("AppBackground"), for: .navigationBar)` — sets the compact nav bar colour for when the user scrolls and the large title collapses.

> **Do not** add `.toolbarBackground(.visible, for: .navigationBar)` — that suppresses large title display by forcing the compact bar permanently.

**List screens** additionally need two lines per `List`:

```swift
List { ... }
    .scrollContentBackground(.hidden)   // reveals AppBackground behind the list

ForEach(items) { item in
    RowView(item: item)
        .listRowBackground(Color("CellBackground"))
}
```

`.scrollContentBackground(.hidden)` cannot be set globally; it must be applied to each `List`. Cell background is applied per `ForEach` (one line per list).

#### Future theming (F-4.01–02)

When user-selectable colour themes are implemented, the `AppBackground` and `CellBackground` asset slots will be the natural extension point — either by swapping asset catalog appearances or by driving `Color` values from a theme state stored in `NSUbiquitousKeyValueStore`. The `appBackground()` modifier call sites will not need to change.

---

## 6. Performance Considerations

The PRD specifies no explicit performance constraints, but these practices keep the app responsive:

- **SwiftData `@Query` with predicates**: Fetch only expenses for the current period, not the full history, when computing "remaining."
- **Lazy loading**: Use `LazyVStack` in scrollable lists.
- **Background Over/Under roll**: If a user hasn't opened the app in weeks, multiple period boundaries may need processing. Do this on a background context to avoid blocking the main thread.
- **Instrument periodically**: Profile with Instruments (Time Profiler, Core Data) during development milestones.

---

## 7. Security and Privacy

- **Encryption at rest**: Apple encrypts app data by default (Data Protection). No additional encryption is needed.
- **No network calls**: Beyond CloudKit sync (managed by the OS), the app makes no network requests.
- **On-device diagnostics**: Uses Apple's unified logging (`OSLog`) with per-subsystem categories (`bootstrap`, `cloudkit`, `ui`). Logs stay on device and are not transmitted.
- **Analytics**: An `AnalyticsClient` protocol abstraction exists for future product analytics. Today's default implementation (`ConsoleAnalyticsClient`) only writes events to the local unified log in **Debug builds** (gated by `#if DEBUG`); release builds are silent no-ops and transmit nothing. Before any network-bound implementation (e.g., Mixpanel) ships, it must be opt-in, exclude PII, and be documented here with the chosen vendor.
- **App Transport Security**: Default configuration is sufficient (no custom domains).
- **Keychain**: Not needed unless future features require secrets (e.g., API keys for AI features in T-7).

---

## 8. Developer Tooling

Local quality gates use **Lefthook** ([lefthook.dev](https://lefthook.dev/)) so hooks stay fast and dependency-light (**Lefthook hooks do not require a Python runtime**; they are not the Python `pre-commit` framework). **`make test`** still invokes **`python3`** for [`scripts/resolve_booted_sim_udid.py`](../scripts/resolve_booted_sim_udid.py), so a Python **3.9+** on `PATH` is required for the full test script.

### 8.1 One-time machine setup

From the repo root, install Homebrew CLI tools, verify Xcode / Python 3, and install Git hooks:

```bash
make system   # runs scripts/system-setup.sh (idempotent)
```

Equivalent manual steps:

```bash
brew install lefthook swiftlint swiftformat gitleaks
make hooks-install   # runs `lefthook install` → writes into .git/hooks/
```

`make system` already runs `lefthook install`; use `make hooks-install` alone if you only need to refresh hooks after pulling hook config changes.

**OpenSpec:** The `openspec` CLI (spec-driven workflow in Cursor/skills) is optional for building and testing the app; install it separately per OpenSpec vendor documentation if you use that workflow.

### 8.2 What runs where

| When | What |
|------|------|
| **pre-commit** | **SwiftFormat** (2-space indent, Swift 6; see [`.swiftformat`](../.swiftformat)) — auto-formats staged `*.swift` and re-stages fixes; **SwiftLint** strict on staged files ([`.swiftlint.yml`](../.swiftlint.yml)); merge-conflict marker scan; **large-file** guard ([`scripts/check-large-files.sh`](../scripts/check-large-files.sh)) — rejects any staged file over 1 MiB; **gitleaks** on staged changes |
| **pre-push** | **`xcodebuild build`** for scheme `simple-recurring-budgets`, iOS Simulator destination `name=iPhone 17,OS=latest` (same default device family as [`scripts/test.sh`](../scripts/test.sh)) |

`gitleaks` is optional for solo work but strongly recommended before any secrets or API keys exist in the tree.

### 8.3 Manual commands

- `make system` — machine bootstrap: Homebrew packages above, Python 3.9+ and `xcodebuild` checks, `lefthook install` (see [`scripts/system-setup.sh`](../scripts/system-setup.sh))
- `make lint` — `swiftlint lint --strict` over the repo
- `make format` — `swiftformat .` (format everything, not only staged files)
- `make test` — full unit/UI test run via [`scripts/test.sh`](../scripts/test.sh) (unchanged)

### 8.4 Pre-push build caveat

The pre-push build needs a resolvable iOS Simulator (booted device or `SIMULATOR_UDID` / `SIMULATOR_NAME` as in `scripts/test.sh`). If destination resolution fails, run tests once with `make test` or boot a simulator, then push again.

---

## 9. Future Technical Considerations

Items from the feature backlog (T-4 through T-7) that will require technical design when prioritized:

| Feature | Technical Surface |
|---------|-------------------|
| **F-4.01–02: Color themes** | Asset Catalog color sets, theme state in `NSUbiquitousKeyValueStore` (synced via iCloud) or SwiftData, `@Environment(\.colorScheme)` integration |
| **F-4.03: Budget icons** | Emoji storage as `String` on `Budget`; SF Symbols picker; optional LLM call for default suggestion |
| **F-4.04: Photo upload for icon** | PhotosUI (`PhotosPicker`), image resizing, binary storage (or file URL) in SwiftData, CloudKit asset limits |
| **F-5.01: Start of week** | `NSUbiquitousKeyValueStore` storage (synced via iCloud), `Calendar` mutation, cascade to Over/Under reset boundary calculations |
| **F-6.01: Adding funds** | Negative expense amount or separate `Transaction` type with a direction enum |
| **F-6.02: Expense Type** | New `expenseType: String?` on `ExpenseItem`, user-defined values stored as a `Set<String>` in `NSUbiquitousKeyValueStore` (synced via iCloud) or a dedicated entity |
| **F-7.01: Receipt scanning** | Vision framework (`VNRecognizeTextRequest`), on-device OCR, regex extraction for amounts |
| **F-7.02–03: Voice input/query** | SiriKit intents or App Intents framework, on-device NLP, `SFSpeechRecognizer` for in-app voice |

---

## 10. Decision Log

| # | Decision | Rationale |
|---|----------|-----------|

---

## Appendix

### A. Glossary

See [main-prd.md §10.1](main-prd.md#101-glossary) for product terms. Technical terms used in this document:

- **`@Model`** — SwiftData macro that marks a class as a persistent model.
- **`@Observable`** — Swift macro for observation-tracked reference types (replaces `ObservableObject`).
- **`@Query`** — SwiftData property wrapper for reactive data fetching in SwiftUI views.
- **`ModelContainer`** — SwiftData object that manages the schema, storage, and sync configuration.
- **CKRecord** — CloudKit's record type; SwiftData models map to CKRecords when CloudKit sync is enabled.

### B. Revision History

| Version | Date       | Author   | Changes          |
| ------- | ---------- | -------- | ---------------- |
| 0.11    | 2026-04-29 | Jimmy Ho | §2.1: list `BudgetDetailView` as a View+Services example with its three lifecycle-refresh triggers; §5.1: document count-driven plural variation pattern and inline vs list-label period-name rule |
| 0.10     | 2026-04-29 | Jimmy Ho | §8: `make system` / `scripts/system-setup.sh`; clarify Python 3 for `make test` vs Lefthook; optional OpenSpec CLI note |
| 0.9     | 2026-04-29 | Jimmy Ho | Add §8 Developer Tooling (Lefthook, SwiftLint, SwiftFormat, gitleaks, large-file script, Makefile targets); renumber former §8–§9 to §9–§10 |
| 0.1     | 2026-04-10 | Jimmy Ho | Initial draft    |
| 0.2     | 2026-04-11 | Jimmy Ho | Add §4.5 (NSUbiquitousKeyValueStore for app settings); update §8 future table to reflect iCloud key-value store instead of UserDefaults |
| 0.3     | 2026-04-13 | Jimmy Ho | Add §5.4 documenting the `PeriodCalculator` / `BudgetCalculator` service layer (public API, biweekly anchor convention, ViewModel consumption pattern) |
| 0.4     | 2026-04-17 | Jimmy Ho | Update §5.4 to add `BudgetLifecycleService` as the sole orchestrator of the eager roll → persist → reset → persist sequence; clarify ViewModel consumption contract |
| 0.5     | 2026-04-17 | Jimmy Ho | Add §4.6 (`FirstRunSeeder`, two-gate decision, `"seededV1"` KV key, flag-write ordering); add KV key table to §4.5; add §5.5 Bootstrap |
| 0.6     | 2026-04-28 | Jimmy Ho | Add `"currencyDisplay"` KV-key row to §4.5 table; document `SyncStatus` environment value plumbing (containerBacking, accountStatus, rowState) in §4.5 |
| 0.6     | 2026-04-17 | Jimmy Ho | Replace §2.1 MVVM framing with "View + Services, ViewModels on demand" (escalation criteria, VM rules, grey-area ping protocol); update §5.4 consumer wording to "screens (and any VMs)" |
| 0.7     | 2026-04-24 | Jimmy Ho | Remove §4.6 (FirstRunSeeder) and §5.5 (Bootstrap); drop `"seededV1"` from §4.5 KV key table; add orphaned-key note; see change `remove-first-run-seeder` |
| 0.8     | 2026-04-26 | Jimmy Ho | Add §5.5 (Color Palette and Theming): `AppBackground`/`CellBackground` asset definitions, `appBackground()` modifier usage pattern, list screen wiring, and future theming notes |
