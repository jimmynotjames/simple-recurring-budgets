# Technical Design Document

| Field              | Value                          |
| ------------------ | ------------------------------ |
| **Version**        | 0.1                            |
| **Last Updated**   | 2026-04-17                     |
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

### 2.1 Pattern: MVVM with `@Observable`

Each screen gets a SwiftUI View and, when it has meaningful logic beyond simple property display, a companion `@Observable` ViewModel. Pure display-only subviews (e.g., a row cell) can remain logic-free without a VM. This keeps view logic testable without spinning up UI, and aligns with Apple's modern observation direction.

### 2.2 Navigation: `NavigationStack` with value-based routing

The app's information architecture is a simple stack: Budgets list → Budget detail → Expense detail. A `NavigationStack` with a `Hashable` route enum and `navigationDestination(for:)` handles this cleanly — type-safe, state-driven, and deep-linkable. iPad/Mac can use adaptive layout without requiring a full split view.

---

## 3. Data Model

### 3.1 Approach

Two SwiftData `@Model` entities: **Budget** and **ExpenseItem**, linked by a one-to-many relationship (Budget → ExpenseItem, cascade delete). Supporting enums (`BudgetPeriod`, `ResetCadence`) are `String`-backed `Codable` types stored inline.

**CloudKit optional relationship pattern:** CloudKit requires all relationships to be optional (records may arrive out-of-order during sync). The stored `Budget.expenses` property is therefore typed `[ExpenseItem]?`. A non-optional computed property `expenseItems: [ExpenseItem]` (`get { expenses ?? [] }`, settable) is the canonical accessor for all app code, so no call site ever handles optionality. The raw `expenses` property should not be accessed outside of the model definition.

Key fields on Budget include allocation, period, currency code (ISO 4217), and Over/Under state (cumulative amount + last reset date + reset cadence). ExpenseItem carries amount, optional name, and date. All monetary values use `Decimal`.

Derived values — **Remaining for current Budget Period** and **Over/Under display** — are computed at read-time, not persisted.

### 3.2 Over/Under Bookkeeping

Per [PRD §6.7](main-prd.md#67-overunder-carryover-behavior):

- **Period boundary roll**: When the app detects a new Budget Period has started, compute `allocation − expenses` for the completed period(s) and fold into the stored Over/Under amount. This happens eagerly on app launch / budget access.
- **Scheduled reset**: Compare last reset date against current date and the budget's reset cadence. If a reset boundary has passed, zero out Over/Under and update the last reset date.
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
| `"seededV1"` | `Bool` | `FirstRunSeeder` | Records that first-run seeding has occurred for this iCloud account; see §5.5 |

### 4.6 First-Run Bootstrap (FirstRunSeeder)

`App/FirstRunSeeder.swift` (a caseless `enum`) seeds one default `Budget` (name: `"Food"`, period: daily, allocation: 25, reset cadence: weekly) on first launch when the data store is empty. It is invoked via a `.task` modifier on the Budgets root in `ContentView`.

**Two-gate decision** — seeding is attempted only when both are true:
1. **Gate A (KV flag):** `NSUbiquitousKeyValueStore` has no value for `"seededV1"`. Prevents reseeding after the user intentionally deletes all their budgets, and on a reinstall where the KV flag arrives before CloudKit.
2. **Gate B (store count):** `context.fetchCount(FetchDescriptor<Budget>()) == 0`. Prevents seeding when CloudKit sync delivers existing budgets before the KV flag arrives on a fresh install of a device that already had the app.

When Gate A is open but Gate B is closed (CloudKit beat the KV sync), the seeder **forward-seals** the KV flag without inserting a budget, so a later delete-all cannot trigger a reseed.

**Flag write ordering:** the `"seededV1"` flag is written only *after* `context.save()` succeeds. A crash between save and flag write causes at most one duplicate seed on next launch (user can delete it) — preferable to writing first and permanently suppressing seeding on a save failure.

The `"seededV1"` key is versioned by name. Future changes that want to force a one-time re-seed for all users should introduce a new key (e.g., `"seededV2"`) rather than reusing this one.

All collaborators (`ModelContext`, `KeyValueStore`, `now: Date`) are injected, making the service fully unit-testable with `MockKeyValueStore` and an in-memory `ModelContainer`.

---

## 5. Internationalization, Accessibility, and Testing

### 5.1 Internationalization

All user-facing text uses Xcode **String Catalogs** and `LocalizedStringKey` — no hard-coded English in production views. Dates and numbers use Foundation format styles that auto-adapt to locale. Each Budget stores its own ISO 4217 currency code; formatting uses `Decimal.FormatStyle.Currency`.

The canonical catalog lives at `simple-recurring-budgets/Resources/Localizable.xcstrings` and is picked up automatically by the app target's `PBXFileSystemSynchronizedRootGroup`; no `project.pbxproj` changes are needed when adding or renaming strings. Every new user-facing string in a production view must use `Text("key", comment: "translator context")` or `LocalizedStringKey("key")`. The `comment:` argument is required whenever the source string would be ambiguous out of context (short labels, button titles, destructive action names, etc.). Placeholder strings in `Views/ContentView.swift` are exempt until the real T-2 screens replace them.

### 5.2 Accessibility

- **Dynamic Type**: System text styles everywhere; no fixed frame heights that clip at larger sizes.
- **VoiceOver**: Meaningful accessibility labels on all interactive controls; financial amounts include currency context.
- **Dark Mode**: Semantic system colors and Asset Catalog color sets with light/dark variants; no hard-coded color literals.

### 5.3 Testing

**Swift Testing** for all new tests; XCTest for UI tests where needed. In-memory `ModelContainer` for all automated data tests to ensure isolation. Business logic (budget math, Over/Under rolls, date boundaries) lives in pure, testable services with no SwiftData/UI dependencies.

### 5.4 Budget Math Service Layer

Three services in `Domain/` implement all budget math and lifecycle orchestration with no SwiftUI dependencies:

- **`PeriodCalculator`** — Pure date-only math (no SwiftData): computes period start/end dates and enumerates period boundaries between two dates. All methods accept an injected `Calendar` for deterministic, timezone-safe results in tests.
- **`BudgetCalculator`** — Pure financial math (no SwiftData) built on `PeriodCalculator`: computes remaining for the current period, rolls carry-over across completed periods, and detects scheduled reset boundaries. Returns structured result types (`CarryOverRollResult`, `ResetCheckResult`) so callers have all the data they need to write back to the model.
- **`BudgetLifecycleService`** — The sole orchestrator that binds `BudgetCalculator` outputs to SwiftData. Takes a `Budget`, `AppSettings`, and `ModelContext`; runs the strict PRD §6.7 sequence (roll → persist → reset if needed → persist); and returns a `BudgetLifecycleResult` with `remaining`, `carryOverAmount`, `periodStart`, and `periodEnd` — everything a ViewModel needs for display. Writes `carryOverAmount`, `carryOverLastProcessedDate`, `carryOverLastResetDate`, and `lastModified` back to the `Budget` in a single `context.save()`, and only when at least one field changed.

**Biweekly anchor:** For biweekly periods, the cycle anchor is derived from `createdAt` + `weekStart` at call time — no extra stored field is needed. Changing `weekStartDay` cascades to biweekly alignment (acknowledged by F-5.01).

**ViewModel consumption:** ViewModels call `BudgetLifecycleService.refreshAndSave(_:settings:context:)` eagerly on budget access (screen appearance and `scenePhase == .active`) and bind the returned `BudgetLifecycleResult` to the view. ViewModels do **not** call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly for the eager access flow — `BudgetLifecycleService` is the single entry point for that sequence.

### 5.5 Bootstrap

`FirstRunSeeder` (see §4.6) is the sole owner of the first-launch seed operation. It lives in `App/` (not `Domain/`), reflecting that it is an app-lifecycle concern rather than a budget-math concern. Its `SeedResult` return type enables precise unit-test assertions for each gate branch. Tests live in `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift`.

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
- **No analytics or tracking**: Aligns with the privacy-first approach.
- **App Transport Security**: Default configuration is sufficient (no custom domains).
- **Keychain**: Not needed unless future features require secrets (e.g., API keys for AI features in T-7).

---

## 8. Future Technical Considerations

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

## 9. Decision Log

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
| 0.1     | 2026-04-10 | Jimmy Ho | Initial draft    |
| 0.2     | 2026-04-11 | Jimmy Ho | Add §4.5 (NSUbiquitousKeyValueStore for app settings); update §8 future table to reflect iCloud key-value store instead of UserDefaults |
| 0.3     | 2026-04-13 | Jimmy Ho | Add §5.4 documenting the `PeriodCalculator` / `BudgetCalculator` service layer (public API, biweekly anchor convention, ViewModel consumption pattern) |
| 0.4     | 2026-04-17 | Jimmy Ho | Update §5.4 to add `BudgetLifecycleService` as the sole orchestrator of the eager roll → persist → reset → persist sequence; clarify ViewModel consumption contract |
| 0.5     | 2026-04-17 | Jimmy Ho | Add §4.6 (`FirstRunSeeder`, two-gate decision, `"seededV1"` KV key, flag-write ordering); add KV key table to §4.5; add §5.5 Bootstrap |
