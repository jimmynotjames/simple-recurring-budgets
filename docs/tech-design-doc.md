# Technical Design Document


| Field              | Value      |
| ------------------ | ---------- |
| **Version**        | 1.0        |
| **Last Updated**   | 2026-07-26 |
| **Author / Owner** | Jimmy Ho   |


> Master technical reference for **Wren**. Complements [main-prd.md](main-prd.md) (product source of truth) and [product-features-planning.md](product-features-planning.md) (feature backlog). Intended as durable context for both human and agentic development.

---

## 1. System Overview

**Wren** is a native Apple-platform app (iOS, iPadOS, macOS) that helps users track spending against recurring budgets. There is no app-owned backend; all data lives on-device via SwiftData and syncs across the user's devices through CloudKit.

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

**Default:** Screens are SwiftUI Views that read data with `@Query`, write through `@Environment(\.modelContext)`, and delegate non-trivial logic to pure domain services in `Domain/` (`BudgetLifecycleService`, `BudgetCalculator`, `PeriodCalculator`). No companion ViewModel by default.

**Why not a VM on every screen.** `Domain/` already carries the testable business logic as pure, SwiftData-free services (see §5.4). A VM on a thin list or detail screen relays calls, duplicates state, and adds lifecycle plumbing (`ModelContext` injection, `bind` timing, preview setup) for no payoff. Reads via `@Query` in the view keep SwiftUI's automatic invalidation on SwiftData changes, which a VM-held fetch would have to reimplement.

**Escalate to an** `@Observable` **ViewModel only when at least one of these is true:**

1. The screen holds **non-trivial draft/form state** not persisted until the user commits (e.g., an Add/Edit screen with cross-field validation).
2. The screen owns `async` **/** `Task` **work** or concurrency-scoped state (e.g., future F-7.01 receipt OCR via Vision, F-7.02 speech recognition).
3. The screen needs **a multi-step user action** chaining validation, multiple writes, and side effects beyond a one-liner.
4. The screen has **derived display state expensive to recompute** inside `body` that benefits from caching outside it.

**Rules for an escalated VM:**

- Name and shape: `@Observable final class <Screen>ViewModel`, owned by the view via `@State`.
- The VM holds draft state and pure logic only. It does not store `ModelContext`, hold `@Query` results, or fetch.
- Methods that write take `(context: ModelContext, ...)` at the call site (and `AppSettings` when relevant). This avoids the `init(context:)` / `bind(context:)` lifecycle trap: `@Environment(\.modelContext)` is only readable inside `body`, and per-call passing keeps Sendable/ownership simple.
- Reads stay in the view via `@Query`.

**Grey-area protocol: ask before scaffolding a VM.** A VM is harder to remove than to add. If a screen is on the fence, ask the user for an explicit judgment call **before** creating a VM file. Grey-area triggers that require a ping:

- More than 3 mutable form fields.
- A framework call inside the screen (Vision, Speech, PhotosUI, SiriKit / App Intents, `SFSpeechRecognizer`, network).
- A single user input that mutates more than one model property or couples fields.
- The screen is expected to grow materially within the next 1–2 features.

Pure display-only subviews (row cells, badges, amount formatters) stay logic-free regardless of the parent screen.

**Implemented View + Services screens:**

- `BudgetsView` — root list; `@Query` drives the row list; `BudgetLifecycleService.result(for:)` called from each row's `.task(id:)`, `onChange(of: scenePhase)`, and `onChange(of: budget.recomputeToken)`.
- `BudgetDetailView` — Budget detail; lifecycle refresh invoked from `.task(id: budget.persistentModelID)`, `onChange(of: scenePhase)`, and `onChange(of: budget.recomputeToken)`. Destructive actions are short imperative methods on the view that write through `@Environment(\.modelContext)` and call `BudgetLifecycleService` afterward.

**Escalated ViewModel screens (draft/form state):**

- `AddEditBudgetViewModel` — Add/Edit Budget sheet: cross-field validation, orphan-expense warning, allocation/start/end save paths, and `budget_edited` analytics property flags.
- `AddEditExpenseViewModel` — Add/Edit Expense: date-bounds validation, Add Funds toggle + sign-on-save, recents candidates (F-7.04).



### 2.2 Navigation: `NavigationStack` with value-based routing

The information architecture is a simple stack: Budgets list → Budget detail → Expense detail. A `NavigationStack` with a `Hashable` route enum and `navigationDestination(for:)` is type-safe, state-driven, and deep-linkable. iPad/Mac use adaptive layout without a full split view.

Route enums (`AppRoute`, `SheetRoute`) carry the model's stable `id` (`UUID`), never a live model reference, so routes stay serializable for future deep links, widgets, and App Intents. `RootView` resolves the UUID at the destination via `ModelContext.budget(id:)` / `.expenseItem(id:)` (`Models/ModelContext+Lookup.swift`). An unresolvable ID (the model was deleted, e.g. on another device, after the route was set) silently pops the push or dismisses the sheet.

A small `@Observable Router` (`path: [AppRoute]`, `sheet: SheetRoute?`) is owned by the app entry point (`simple_recurring_budgetsApp`) as `@State` and injected via `.environment(router)`. `RootView` and descendant screens read it via `@Environment(Router.self)`, so leaf screens trigger pushes and sheets without holding navigation state.

`AppRoute` push cases: `budgetDetail(UUID)` (Budgets list → Budget detail), `expenseDetail(UUID)` (Budget detail → Expense edit, F-2.04 edit path). `SheetRoute` sheet cases: `addBudget`, `editBudget(UUID)`, `addExpense(UUID)`, `settings`, `analyticsConsent`. Existing-expense editing is a push (`AppRoute.expenseDetail`), not a sheet.

`AddEditExpenseView` does not own a `NavigationStack`; the caller provides it. For the sheet path (`addExpense`), `RootView` wraps it in `NavigationStack { }`. For the push path (`expenseDetail`), the outer `NavigationStack` in `RootView` provides it.

---



## 3. Data Model



### 3.1 Approach

Four SwiftData `@Model` entities: **Budget**, **ExpenseItem**, **AllocationChange**, and **LifecycleEvent**, all held in `SchemaV1`. `Budget → ExpenseItem`, `Budget → AllocationChange`, and `Budget → LifecycleEvent` are cascade-delete one-to-many relationships. Supporting enums (`BudgetPeriod`, `LifecycleEventKind`) are `String`-backed `Codable` types stored as raw `String` columns with typed computed accessors, which keeps the columns visible to `#Predicate` (Codable-backed enum storage is opaque to predicates).

Users delete a `Budget` with the **Delete Budget** button on the Add/Edit Budget sheet (Edit mode only). Confirming calls `context.delete(budget)` + `context.save()` on `AddEditBudgetViewModel`; the `@Relationship(deleteRule: .cascade)` rules remove the budget's `ExpenseItem`, `AllocationChange`, and `LifecycleEvent` rows in the same save. No schema or CKRecord change is involved.

**CloudKit optional relationship pattern:** CloudKit requires all relationships to be optional (records may arrive out of order during sync). All stored relationship properties (`Budget.expenses`, `Budget.allocationChangesStorage`, `Budget.lifecycleEventsStorage`, `ExpenseItem.budget`, `AllocationChange.budget`, `LifecycleEvent.budget`) are typed optional. App code uses the non-optional computed accessors (`expenseItems`, `allocationChanges`, `lifecycleEvents`), which return `?? []`.

**Budget entity fields:**


| Property                   | Type                  | Notes                                                                                               |
| -------------------------- | --------------------- | --------------------------------------------------------------------------------------------------- |
| `id`                       | `UUID`                | Stable identity                                                                                     |
| `name`                     | `String`              | Display name                                                                                        |
| `currencyCode`             | `String`              | ISO 4217 code                                                                                       |
| `period`                   | `String`              | `BudgetPeriod.rawValue`                                                                             |
| `sortOrder`                | `Int`                 | User-defined list ordering                                                                          |
| `createdAt`                | `Date`                | Immutable after creation                                                                            |
| `lastModified`             | `Date`                | Bumped on every user-initiated mutation that affects math                                           |
| `startDate`                | `Date?`               | When the budget begins; semantically always populated for saved budgets (CloudKit optionality only) |
| `endDate`                  | `Date?`               | Terminal cutoff; `nil` for open-ended recurring budgets                                             |
| `lastResetDate`            | `Date?`               | Most recent manual Reset Carry-Over or Reset Budget timestamp; `nil` means no reset                 |
| `isCarryOverEnabled`       | `Bool`                | Display toggle; algorithm always computes carry-over internally                                     |
| `icon`                     | `String?`             | Optional emoji budget icon (F-4.03); `nil` when unset                                               |
| `allocationChangesStorage` | `[AllocationChange]?` | Allocation history; use `allocationChanges` computed accessor                                       |
| `lifecycleEventsStorage`   | `[LifecycleEvent]?`   | Pause/resume history; use `lifecycleEvents` computed accessor                                       |
| `expenses`                 | `[ExpenseItem]?`      | Expense rows; use `expenseItems` computed accessor                                                  |


**AllocationChange entity fields:** `id`, `effectiveFrom: Date`, `amount: Decimal`, `lastModified: Date`, `budget: Budget?`.
**LifecycleEvent entity fields:** `id`, `kindRawValue: String` (raw value of `LifecycleEventKind`; exposed via a typed `kind` accessor — storing the raw string preserves `#Predicate` filter compatibility), `effectiveDate: Date`, `lastModified: Date`, `budget: Budget?`.
**ExpenseItem entity fields:** `id`, `amount: Decimal` (signed; negative = add-funds), `name: String?`, `date: Date`, `createdAt: Date`, `lastModified: Date`, `expenseType: String?`, `budget: Budget?`.

All monetary values use `Decimal`, never floating-point.

Derived values (**Remaining for current Budget Period**, **Carry-over**) are computed at read time via `BudgetCalculator.snapshot(...)` and never persisted.

### 3.2 Carry-Over Bookkeeping

Per [PRD §6.7](main-prd.md#67-carry-over-behavior), the algorithm is a **live walker** (no stored carry-over amount):

- `BudgetCalculator.snapshot(budget:expenses:now:calendar:)` is the single pure read entry point: stateless, never mutates the budget.
- The walker sums `(allocationInEffect(at: periodStart) − expenses)` for every completed active period in `[max(startDate, lastResetDate ?? .distantPast), currentPeriodStart)`.
- The **asymmetric live coupling rule** adds the current period's *committed* overflow (overspend and add-funds excess) to the walker sum in real time. Ordinary mid-period slack waits for the period close.
- **Manual reset**: `BudgetLifecycleService.resetCarryOver(_:context:)` sets `lastResetDate = now`, trimming the walker window so carry-over reads zero from then on.



### 3.3 Migration Strategy

Wren v1.0 shipped to the App Store on 2026-07-22, and the CloudKit **production** schema was deployed 2026-07-12. Real user data now exists on real devices, so `SchemaV1` is a frozen, deployed baseline — it is no longer safe to edit in place.

Any change to a persisted model MUST:

- Add a new `VersionedSchema` (`SchemaV2`, …) rather than editing `SchemaV1` in place.
- Add a `MigrationStage` to `BudgetMigrationPlan.stages`.
- Ship a migration test — copy the pattern in `simple-recurring-budgetsTests/Models/BudgetMigrationPlanTests.swift`, which uses the `MigrationTestSupport` helper (temp-URL fixture writer + reopen-through-plan).
- Be additive only — CloudKit can never delete a field from a deployed record type, and all new relationships must be optional.

Never wipe or reshape the store as a fix. "Wipe the simulator and move on" was the pre-1.0 convention; it destroys user data now.

---



## 4. Persistence and Sync



### 4.1 SwiftData + CloudKit

`cloudKitDatabase: .automatic` on `ModelConfiguration` enables CloudKit sync with the default container, the simplest integration for SwiftData-backed CloudKit apps.

**Single-store guarantee (split-brain prevention).** `makeProductionModelContainer` tries a CloudKit-enabled config first and falls back to a local-only (`cloudKitDatabase: .none`) config when iCloud is unavailable (offline / not signed in). Both configs are pinned to one shared on-disk store `url`, obtained from `ModelConfiguration(schema:isStoredInMemoryOnly:false).url` (SwiftData's default path, so existing installs keep their store). The two configs therefore never resolve to different files: an offline first launch writes to the store, and a later online launch opens that **same** store and attaches CloudKit mirroring in place, promoting local data to the cloud instead of stranding it in a forked, empty store. `PersistentStoreURLTests` lock in the invariant that a config's `url` is independent of its `cloudKitDatabase` setting.

### 4.2 CloudKit Setup Requirements

- **iCloud container identifier**: `iCloud.com.jimmyho.simple-recurring-budgets` (set in entitlements).
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

App-wide preferences (e.g., default carry-over toggle, start-of-week day) use `NSUbiquitousKeyValueStore` instead of `UserDefaults`, so settings sync across devices on the same Apple ID without SwiftData or a custom mechanism. The store shares the app's existing iCloud container entitlement.

Constraints:

- 1 MB total / 1024 keys maximum.
- Eventually consistent: the local value is authoritative until sync arrives.
- Observe `NSUbiquitousKeyValueStore.didChangeExternallyNotification` to update in-memory state when another device writes.
- No `register(defaults:)` equivalent: check for key existence and apply hard-coded defaults on first read.
- Testability via a `KeyValueStore` protocol seam (`NSUbiquitousKeyValueStore` cannot be instantiated with a custom suite).

**Keys in use:**


| Key                                  | Type                                                                  | Owner               | Purpose                                                                                                                                                                                                                                                                               |
| ------------------------------------ | --------------------------------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `"defaultCarryOverEnabled"`          | `Bool`                                                                | `AppSettings`       | Default carry-over toggle for new budgets                                                                                                                                                                                                                                             |
| `"weekStartDay"`                     | `Int64` (`Weekday.rawValue`)                                          | `AppSettings`       | First day of the week (locale default if absent)                                                                                                                                                                                                                                      |
| `"currencyDisplay"`                  | `String` (`CurrencyDisplayPreference.rawValue`)                       | `AppSettings`       | Currency display format for monetary amounts (symbol / code / codeAndSymbol); default `.symbol`                                                                                                                                                                                       |
| `"analyticsOptIn"`                   | `Bool`                                                                | `AppSettings`       | User's analytics opt-in preference. Written only on first explicit user action; absent key means "not yet decided". Default is locale-aware (`ConsentJurisdiction`): `.required` regions default to `false`; `.autoOptin` regions default to `true`. See `docs/analytics-spec.md` §7. |
| `"analyticsDistinctId"`              | `String` (UUIDv4)                                                     | `AppSettings`       | Stable Mixpanel distinct ID generated on first read and synced via iCloud KV. Read-only after creation. See `docs/analytics-spec.md` §6.                                                                                                                                              |
| `"analyticsFirstOpenAt"`             | `Double` (seconds since epoch, `Date.timeIntervalSinceReferenceDate`) | `AppSettings`       | Timestamp of first app open, generated on first read. Used for `time_since_first_app_open_bucket` super-property. See `docs/analytics-spec.md` §10.2.                                                                                                                                 |
| `"ratingPromptInstalledAt"`          | `String` (`Date.timeIntervalSinceReferenceDate`)                      | `RatingPromptState` | First-launch timestamp for the F-6.03 rating prompt, stamped once. **Not** analytics-gated — distinct from `analyticsFirstOpenAt`.                                                                                                                                                    |
| `"ratingPromptLoggedExpenseCount"`   | `Int64`                                                               | `RatingPromptState` | Lifetime count of successful Add-mode expense logs (F-6.03 eligibility).                                                                                                                                                                                                              |
| `"ratingPromptDistinctLogDayCount"`  | `Int64`                                                               | `RatingPromptState` | Count of distinct calendar days an expense was logged (F-6.03 eligibility).                                                                                                                                                                                                           |
| `"ratingPromptLastLogDayStart"`      | `String` (`Date.timeIntervalSinceReferenceDate`)                      | `RatingPromptState` | Start-of-day of the most recent logging day; detects a new distinct day.                                                                                                                                                                                                              |
| `"ratingPromptFirstEligibleAt"`      | `String` (`Date.timeIntervalSinceReferenceDate`)                      | `RatingPromptState` | When the rating thresholds were first met; one-shot gate for `rating_prompt_eligible`.                                                                                                                                                                                                |
| `"ratingPromptLastRequestedVersion"` | `String` (`CFBundleShortVersionString`)                               | `RatingPromptState` | App version a review was last requested for; the once-per-version guard (F-6.03).                                                                                                                                                                                                     |


> **Orphaned key:** `"seededV1"` was used by a removed first-run seeder (change `remove-first-run-seeder`) and is a harmless leftover on upgraded installs. It SHALL NOT be reused as a KV key; the `"V1"` suffix stays reserved so any future one-time-reseed change uses a distinct name (e.g., `"seededV2"`).

**SyncStatus environment value:** `SyncStatus` is an `@Observable final class` injected via `.environment(syncStatus)` in `simple_recurring_budgetsApp`. It has two properties: `containerBacking: ContainerBacking` (`.cloudKit` or `.localFallback`), set once at launch from the outcome of `makeProductionModelContainer` and never mutated; and `accountStatus: AccountStatus` (`.checking`, `.available`, or `.unavailable`), updated asynchronously by `SettingsView` via `CKContainer.default().accountStatus()` and live `CKAccountChanged` / `NSUbiquityIdentityDidChange` observers. A derived `rowState: RowState` combines both into the four-state view-state for the Settings iCloud row (`.checking`, `.available`, `.paused`, `.unavailable`). Screens read it via `@Environment(SyncStatus.self) private var syncStatus`.

### 4.6 Container creation recovery (no `fatalError`)

`makeProductionModelContainer` throws. When both CloudKit-backed and local-only `ModelContainer` creation fail, the error goes to the `@Observable AppStartup` model (`simple-recurring-budgets/App/AppStartup.swift`) and the `@main` body presents `ContainerFailureView` (Retry + Send Feedback) instead of crashing (`container-creation-recovery` capability). `Logger.cloudKit.error("cloudkit.container.failed: …")` fires before the throw per the `diagnostic-logging` capability.

Realistic causes of a both-paths failure in production (community-reported, ordered by likelihood for this app):

1. **Disk full** (`NSFileWriteOutOfSpaceError` / Cocoa 640). SQLite's WAL/journal can't grow. Retry won't help until the user frees space.
2. **Schema migration failure.** A future `BudgetMigrationPlan` step throwing (bad mapping, version mismatch, failing `MigrationStage`). Retry occasionally succeeds (transient pressure releases). Wiping the store is the last resort; it is never automatic.
3. **Migration race between the app and any future extension** (see §4.7).
4. **Corrupted SQLite store.** Power loss mid-WAL-checkpoint, OS-update artifact. Retry rarely helps; Send Feedback is the escape hatch.
5. **CloudKit account in transit.** User just signed out / switched Apple IDs / mid-mirror recovery. Often self-resolves on the next launch; Retry works.



### 4.7 Multi-process / extension considerations — **read before shipping any extension target**

⚠️ **This app has no app extension targets** (no widget, Live Activity, Lock Screen widget, Control Center widget, App Clip, or Share / Action / Intents / Notification Service extension). The container model assumes a **single-process owner** of the on-disk store.

**A change that introduces any of these SHALL re-evaluate the following in the same change** (the agent adding the extension owns this checklist):

1. **App Group + shared store URL.** Decide whether the extension reads or writes the same SwiftData store. If yes, move the store to a shared App Group container (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`) and update `makeProductionModelContainer` to anchor `ModelConfiguration.url` there instead of the default app-sandbox path. Treat this as a one-shot migration (copy the existing store file once, gated by an `NSUbiquitousKeyValueStore` flag, then read from the new path). The per-config `url` invariant tested by `PersistentStoreURLTests` extends to the new path.
2. **Migration race condition.** SwiftData / CoreData does **not** serialize `ModelContainer` creation across processes. If the host app and an extension both open the store during a schema migration (e.g. the user updates the app and the system wakes the widget at the same time), one or both `ModelContainer.init` calls can throw with no useful diagnostic. The community-recommended mitigation is a **process-level lockfile** around the `ModelContainer(...)` call (write a sentinel file in the App Group container; the second comer waits on it with a short timeout). Ship it in the same change as the extension.
3. **Read-only vs read-write split.** If the extension only *reads*, give it a read-only `ModelContainer` (or a snapshot exported to a smaller cache file) so it cannot race with the host's migrations.
4. **Background launch + file protection.** If the extension can launch while the device is locked (most widget refreshes can), the store file's data-protection class matters. The default, `NSFileProtectionCompleteUntilFirstUserAuthentication`, is usually fine; verify before shipping.
5. **Retry semantics.** `ContainerFailureView.Retry` only re-runs the host app's container creation. An extension has no recovery surface of its own, so it should fail silently (a stale widget) rather than show error UI, and rely on the host-app launch to repair the store.

For any "add a widget / Live Activity / App Clip / Intents extension" change, the five points above are required reading. Driggers' "All the ways SwiftData's ModelContainer can Error on Creation" (2025) is the canonical writeup of the race condition.

---



## 5. Internationalization, Accessibility, and Testing



### 5.1 Internationalization

All user-facing text uses Xcode **String Catalogs** and `LocalizedStringKey`; no hard-coded English in production views. Dates and numbers use Foundation format styles that adapt to locale. Each Budget stores its own ISO 4217 currency code; formatting uses `Decimal.FormatStyle.Currency`.

The canonical catalog is `simple-recurring-budgets/Resources/Localizable.xcstrings`, picked up automatically by the app target's `PBXFileSystemSynchronizedRootGroup`; adding or renaming strings needs no `project.pbxproj` change. Every new user-facing string in a production view uses `Text("key", comment: "translator context")` or `LocalizedStringKey("key")`. `comment:` is required whenever the source string is ambiguous out of context (short labels, button titles, destructive action names, etc.). Placeholder strings in `Views/RootView.swift` are exempt until the real T-2 screens replace them.

**Count-driven plurals.** When copy varies by count (e.g. "1 item" vs "2 items"), use Xcode String Catalog plural variations (CLDR `one`/`other` per locale), not Swift-side word substitution. The call site passes the integer count as an interpolation (`Text("my.key \(count)")`), which resolves to the catalog key `"my.key %lld"`; the catalog encodes locale-specific `one`/`other` (and `few`/`many` where needed) buckets. Prefer a count-free rewrite ("all expenses", "all items") when it is equally clear; it keeps the catalog simpler and the call site free of runtime arguments.

**Inline vs list-label period names.** `BudgetPeriod.inlineLabel` (`period.daily.inline`, `period.weekly.inline`, `period.biweekly.inline`, `period.monthly.inline`) and `BudgetPeriod.listLabel` use **separate** per-locale keys. Never derive inline forms from list-label forms via `.lowercased()`; translators control case for each context.

**Shared keys for repeated copy.** Strings identical across multiple surfaces use a single `common.`* catalog key. Current shared keys:


| Key                    | Used by                                                                                                  |
| ---------------------- | -------------------------------------------------------------------------------------------------------- |
| `common.action.cancel` | Reset Budget confirmation, Reset Carry-Over alert, Currency Picker toolbar, and any future Cancel reuse. |


This prevents translation drift (one surface translating "Cancel" differently from another) and keeps the catalog smaller. Hoist new shared copy under `common.*` only when it is identical in meaning across surfaces; otherwise use per-surface keys so translators can pick context-appropriate wording.

**Locale-invariant strings use** `Text(verbatim:)`. Content that is purely numeric, code-like, or otherwise not translatable (app version + build number, raw ISO currency codes shown without a localized name, monospaced identifiers, etc.) MUST use `Text(verbatim: "…")` so the literal is **not** auto-extracted into the catalog. Otherwise Xcode emits opaque catalog keys like `"%@ (%@)"` that translators cannot interpret and that bypass the `screen.purpose.detail` naming convention. Where the same row also exposes translatable copy via VoiceOver (e.g. the Settings version row's "Version 1.2.0, build 342" `accessibilityLabel`), localize the **a11y label** with a real catalog key and keep the visible numerals verbatim.

#### Translation pipeline

Translations for all 49 App Store storefront locales are produced and merged by a four-script pipeline at `scripts/translate_catalog/`:


| Script        | Role                                                                                                                                                               |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `locales.py`  | Single source of truth: `LOCALES` list (49 BCP 47 codes) and `LOCALE_NAMES` map                                                                                    |
| `extract.py`  | Reads `Localizable.xcstrings`, emits `tmp/translate-inputs/source.json` with English values + format specifier metadata                                            |
| `merge.py`    | Reads `tmp/translate-outputs/{locale}.json` per locale; writes `localizations[locale]` back into the catalog with `state: "translated"` and stable sorted-key JSON |
| `validate.py` | Post-merge audit: checks for missing keys, format-specifier multiset equality, non-empty values; exits non-zero on hard errors                                     |


**To add a new key:** write the key in the source view with `String(localized:defaultValue:comment:)`, run `extract.py` to refresh `source.json`, re-run the translation subagents for that key's values only, then re-run `merge.py` and `validate.py`.

**Model used:** Composer 2 (`composer-2-fast`). `PROMPT_TEMPLATE.md` in the same directory documents model requirements; swap the slug there to use another model.

**Proper nouns kept in English:** "Wren" (product brand), "iCloud", "Carry-Over" (product concept), and App Store brand terms stay in English in all locales; `validate.py` issues informational warnings (not hard errors) for identical-to-source values.

**App Store listing metadata** is a separate, parallel pipeline at `scripts/translate_metadata/` (driven by the `appstore-translate-metadata` skill / `/appstore:translate-metadata`, gate: `check_metadata.py`). It transcreates the listing copy (`name`, `subtitle`, `keywords`, `promotional_text`, `description`, `release_notes`) from `fastlane/metadata/en-US/` into all 49 storefronts under `fastlane/metadata/<storefront>/`. It is separate from the in-app pipeline because App Store Connect uses *storefront* codes (`de-DE`, `no`, `nl-NL`, `ar-SA`) rather than the app's *runtime* codes; `scripts/translate_metadata/metadata_locales.py` owns the runtime→storefront map. Per-storefront subagents run on Opus (marketing transcreation, not literal translation) and enforce Apple's per-field character limits. "Wren" is kept verbatim in every locale, so no localized home-screen icon name is needed. See `scripts/translate_metadata/README.md`.

### 5.2 Accessibility

- **Dynamic Type**: System text styles everywhere; no fixed frame heights that clip at larger sizes.
- **VoiceOver**: Meaningful accessibility labels on all interactive controls; financial amounts include currency context. Custom composite views (carry-over chip, currency picker rows, current-period section header on Budget detail) collapse to one VoiceOver element via `.accessibilityElement(children: .ignore)` plus an explicit composed `.accessibilityLabel(...)`. Headings use `.accessibilityAddTraits(.isHeader)` so the headings rotor surfaces them: `List`/`Section` header `Text` views and semantic content-area headers (e.g. the budget detail status header). Not `GroupBox` card labels, which are visual section labels, not structural headings. Destructive controls (Reset Budget, Reset Carry-Over, Delete Budget, Delete Expense, swipe-to-delete) carry an `.accessibilityHint(...)` describing the irreversible consequence. `swipeActions` **are not auto-exposed to VoiceOver**; every `swipeActions` block MUST be paired with a matching `.accessibilityAction(named:)` so VO users can invoke it via the rotor. See [docs/audits/localization+voiceover-audit-2026-04-30.md](audits/localization+voiceover-audit-2026-04-30.md) for the per-screen audit baseline.
- **Dark Mode**: Semantic system colors and Asset Catalog color sets with light/dark variants; no hard-coded color literals.



### 5.3 Testing

**Swift Testing** for all new unit tests. XCUITest targets use XCTestCase (Apple does not support `import Testing` in unhosted UI test bundles). Automated data tests use an in-memory `ModelContainer` for isolation. Business logic (budget math, Over/Under rolls, date boundaries) lives in pure services with minimal or no SwiftData/UI dependencies.

**Test runs**: one iPhone simulator, latest OS. Multiple device models or OS versions only for device-specific tests.

**Two-pass UI test strategy** (`make tests`): Unit tests run first (`-skip-testing:simple-recurring-budgetsUITests`) to warm the simulator, because XCUITest needs the sim to have hosted at least one app lifecycle before its IPC socket is reliable. Pass 2 runs the two XCUITest classes with `-only-testing`:

- `AccessibilityAuditTests` — 30 tests using `XCUIApplication.performAccessibilityAudit()` (Xcode 15+) to verify VoiceOver labels, touch-target sizes, Dynamic Type adoption, and text clipping across every major screen.
- `UserJourneyTests` — 15 end-to-end flow tests (create budget, navigate to detail, add expense ×2, edit budget, pause/resume, delete/edit expense, reorder budgets, delete budget, settings round-trip, and 4 Add/Edit-Budget period-chip flows). Uses XCTestCase with `continueAfterFailure = false`.

Five **screen objects** (`BudgetsScreen`, `BudgetDetailScreen`, `AddBudgetScreen`, `AddExpenseScreen`, `SettingsScreen`) in `simple-recurring-budgetsUITests/` encapsulate element queries. When view labels or navigation change, update the matching screen object. `make ui-tests` runs only the UI pass (no unit re-run), useful when iterating on failures.

### 5.4 Budget Math Service Layer

Services in `Domain/` implement all budget math with no SwiftUI dependencies:

- `PeriodCalculator` — Pure date math: period start/end dates and period-boundary enumeration. Accepts `RecurringBudgetPeriod` (excludes `.specificDates` at compile time). All methods take an injected `Calendar` and a `weekStart: Weekday`, the **global** week grid from `AppSettings.weekStartDay`, consumed only by the `.weekly` branch (change `weekly-global-week-start`, #240). Biweekly cycles anchor to `Budget.startDate` alone.
- `BudgetCalculator.snapshot(budget:expenses:now:calendar:weekStart:) -> BudgetSnapshot` — The single pure read entry point; stateless, mutates nothing. Computes carry-over via `walkCarryOver(...)` (live walker over completed active prior periods), adds the asymmetric `currentPeriodSpillover(...)` for the in-progress period, and looks up allocation history via `allocationInEffect(at:history:)`. A dedicated `specificDatesBranch` handles one-window trip budgets. **Two classifiers split math from UI** (see F-7.06): `isActive(periodStart:periodEnd:sortedLifecycleEvents:)` is period-granular and drives the carry-over walker and the `remaining = 0` short-circuit for fully-paused periods; `isPausedAtMoment(now:sortedLifecycleEvents:)` is moment-granular and drives `BudgetSnapshot.lifecycleState`, flipping `.paused` as soon as a `.pause` event's `effectiveDate` is reached. Returns a `BudgetSnapshot` with `lifecycleState`, `effectiveAllocation`, `remaining`, `carryOver` (`nil` for `.specificDates`), `effectivePeriodStart`, `effectivePeriodEnd`. Algorithm details: `[docs/budget-calculations-rewrite-algorithm.md](budget-calculations-rewrite-algorithm.md)`.
- `BudgetLifecycleService` — Compatibility adapter between `BudgetCalculator.snapshot` and the view-layer `BudgetLifecycleResult` contract. `result(for:weekStart:)` is a pure read (calls `snapshot`, maps the result, takes no `ModelContext`); `weekStart: Weekday` has **no default**, so call sites pass `settings.weekStartDay` explicitly. Five write-path methods mutate state and `context.save()`: `applyAllocationEdit(_:newAmount:context:…weekStart:)` (governing-row mutate-or-insert keyed on `max(currentPeriodStart, effectiveStartDate)` — the same instant the live read uses, so live, walker, and write agree even for mid-grid first periods; #247), `resetCarryOver(_:context:)` (sets `lastResetDate`; no period math, no weekStart), `resetBudget(_:context:…weekStart:)` (deletes all expenses + sets `lastResetDate`), `pauseBudget(_:context:now:…weekStart:) -> Bool` (inserts `LifecycleEvent(.pause)` if eligible; rejects for `.specificDates`, already paused, or past `endDate`), `resumeBudget(_:context:now:…weekStart:) -> Bool` (inserts `LifecycleEvent(.resume)` if eligible; same rejections). All write-path methods bump `Budget.lastModified = now` before saving.

**Refresh trigger:** Every user-initiated write (expense add/edit/delete, allocation edit, pause/resume, manual reset) bumps `Budget.lastModified = now` in the same `context.save()`. Views also observe `budget.recomputeToken` (derived from `lastModified`, expense count, and lifecycle/allocation child timestamps; see `Budget+RecomputeToken.swift`), so chip refresh covers expense edits and CloudKit merges that do not re-bump `lastModified`. Refresh is also driven by `.task(id:)`, `onChange(of: scenePhase == .active)`, and `onChange(of: settings.weekStartDay)` (a Week Starts On change, local or iCloud-synced, re-grids weekly budgets immediately).

**Anchors:** The weekly grid is global: `AppSettings.weekStartDay`, passed to the calculator as `weekStart` (#240). The biweekly cycle anchor is `Budget.startDate` (a weekday cannot define a 14-day cycle's phase). `AppSettings.weekStartDay` also seeds the pre-populated start date in the Add Budget form.

**Caller consumption:** Screens call `BudgetLifecycleService.result(for:)` eagerly and bind the returned `BudgetLifecycleResult`. Screens do **not** call `BudgetCalculator.snapshot(...)` directly; `BudgetLifecycleService` is the read-path entry point.

### 5.5 Color Palette and Theming

The app uses a warm earth-tone palette of named color assets in `Resources/Assets.xcassets`, with separate light and dark appearances. Views must use these named assets, never hard-coded color literals.

**Exceptions:** Semantic system colors are used for money signals (`Color.moneySurplus` / `Color.moneyDeficit`, extensions on `Color` in `Views/Shared/Color+Money.swift`), iCloud sync-status icons (system `.green` / `.orange`), and destructive button tints (`.tint(.red)`). They adapt to light/dark via the system palette and need no asset catalog slots. If F-4.01–02 themes need per-theme control, promote them to named assets then.

#### Color assets

Exact values live in `Resources/Assets.xcassets`. The table documents semantic intent only.


| Asset name       | Semantic role                                                                                         |
| ---------------- | ----------------------------------------------------------------------------------------------------- |
| `AppBackground`  | Screen/page background; fills behind nav bar, list, and empty states                                  |
| `CellBackground` | List row background                                                                                   |
| `AccentColor`    | Tint for toolbar icons, text links, toggle tint, foreground accent text, icon-picker selection stroke |
| `AccentFill`     | Solid accent backgrounds behind white text (period chips, `.borderedProminent` buttons)               |


**Generated symbols:** Xcode emits `Color.accentFill` from the `AccentFill` asset (`GeneratedAssetSymbols`). Use `AccentColor` (or `.accentColor`) for tints and foreground accents; use `Color.accentFill` (`.tint(Color.accentFill)`) for filled controls with white labels on a sage background. WCAG contrast is met by the default light/dark asset values, not by `contrast: increased` catalog appearances.

#### Applying to screens

`View+AppBackground.swift` exposes one `appBackground()` modifier; every screen calls it once on its root content view:

```swift
Group { ... }
    .navigationTitle("My Screen")
    .appBackground()
```

It applies:

- `.background(Color("AppBackground").ignoresSafeArea())`: fills the full screen including safe areas; shows through the transparent nav bar while the large title is visible.
- `.toolbarBackground(Color("AppBackground"), for: .navigationBar)`: sets the compact nav bar color once the large title collapses on scroll.

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

`.scrollContentBackground(.hidden)` cannot be set globally; apply it to each `List`. Apply the cell background per `ForEach`.

#### Future theming (F-4.01–02)

User-selectable color themes would extend the `AppBackground` and `CellBackground` slots, by swapping asset catalog appearances or driving `Color` values from theme state in `NSUbiquitousKeyValueStore`. `appBackground()` call sites stay unchanged.

---



## 6. Performance Considerations

The PRD specifies no explicit performance constraints, but these practices keep the app responsive:

- **SwiftData** `@Query` **with predicates**: Fetch only expenses for the current period, not the full history, when computing "remaining."
- **Lazy loading**: Use `LazyVStack` in scrollable lists.
- **Background Over/Under roll**: If a user hasn't opened the app in weeks, multiple period boundaries may need processing. Do this on a background context to avoid blocking the main thread.
- **Instrument periodically**: Profile with Instruments (Time Profiler, Core Data) during development milestones.

---



## 7. Security and Privacy

- **Encryption at rest**: Apple's default Data Protection suffices; no additional encryption.
- **Network surface**: **No app-owned backend**. The OS manages CloudKit sync. The only third-party network client is **Mixpanel** (product analytics), gated by user consent (see the product-analytics bullet below and `docs/analytics-spec.md`). All other release traffic is Apple framework traffic (CloudKit, iCloud KV).
- **On-device diagnostics**: Apple's unified logging (`OSLog`) via `Logger` constants in `AppLoggers.swift` (categories: `bootstrap`, `cloudkit`, `ui`, `persistence`). These four are canonical; adding or renaming one requires a matching update to this section and to the `diagnostic-logging` capability spec. Call-site map: `Logger.bootstrap` — one `info` entry per launch recording the resolved `AppDatabaseLaunchMode`; `Logger.cloudKit` — container-backing entries in `makeProductionModelContainer` plus one `notice` entry per iCloud account-status transition in `SettingsView`; `Logger.ui` — one `debug` entry per user-initiated destructive action (`resetBudget`, `resetCarryOver`, `deleteBudget`, `deleteExpense`), recording the entity's `persistentModelID` at `privacy: .private`; `Logger.persistence` — one `error` entry per SwiftData `context.save()` failure surfaced through the shared persistence-save helper (`ModelContext.saveChanges(operation:analytics:)`), interpolating the `PersistenceOperation` identifier and the underlying `NSError`'s `localizedDescription` at `privacy: .public` (both non-user-derived). Every interpolated value at a `Logger.`* call site carries an explicit `privacy:` argument. Diagnostic call sites write to these loggers directly and never pass through `AnalyticsClient`. The one narrow exception (the `persistence_save_failed` sibling event) is in `docs/analytics-spec.md` [§17](analytics-spec.md#17-boundary-with-f-801-oslog). Logs stay on device.
- **Product analytics**: The `AnalyticsClient` protocol is product-only (no diagnostic routing). The default implementation (`ConsoleAnalyticsClient`) prints events in **Debug builds** only (`#if DEBUG`); release builds are silent no-ops and transmit nothing. `MixpanelAnalyticsClient` is the production implementation (F-8.02, `mixpanel-phase-1-foundation`). Consent is **locale-aware**: default off (explicit opt-in required) in strict-opt-in jurisdictions (EU/EEA/UK/Switzerland and other regimes such as South Korea, China, Brazil, Turkey, Thailand, and Quebec; canonical list in `docs/analytics-spec.md` §7.2), default on (auto opt-in, user can opt out from Settings) elsewhere. No PII is ever transmitted regardless of jurisdiction (`docs/analytics-spec.md` §5). The Mixpanel SDK is initialized **lazily**: `Mixpanel.initialize` is NOT called in `init`; the first opted-in `track`/`identify` call triggers initialization guarded by `NSLock`; an opted-out launch creates no `MixpanelInstance` and makes no network requests. The "Diagnostics & Analytics" toggle in Settings drives `AppSettings.analyticsOptIn`; toggle-off fires `analytics_consent_changed` then calls `reset()` to wipe the Mixpanel identity. The client-selection table (DEBUG → Console; Release opted-out → Console; Release opted-in → Mixpanel lazy), launch-time event ordering, and consent-transition ordering are in `docs/analytics-spec.md` §§8 and 8.1. The pre-F-8.02 scaffold is recorded in `docs/analytics-spec.md` §16.1. Full spec: `docs/analytics-spec.md` §§2–8.
- **App Transport Security**: Default configuration suffices (no custom domains).
- **Keychain**: Not needed unless future features require secrets (e.g., API keys for AI features in T-7).

---



## 8. Developer Tooling

Local quality gates use **Lefthook** ([lefthook.dev](https://lefthook.dev/)); hooks need no Python runtime (this is not the Python `pre-commit` framework). `make tests` still invokes `python3` for `[scripts/resolve_booted_sim_udid.py](../scripts/resolve_booted_sim_udid.py)`, so Python **3.9+** must be on `PATH` for the full test script.

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

`make system` already runs `lefthook install`; use `make hooks-install` alone to refresh hooks after pulling hook config changes.

**OpenSpec:** The `openspec` CLI (spec-driven workflow in Cursor/skills) is optional for building and testing; install it per OpenSpec vendor documentation if you use that workflow.

### 8.2 What runs where


| When           | What                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **pre-commit** | **SwiftFormat** (2-space indent, Swift 6, max 200 chars/line; see `[.swiftformat](../.swiftformat)`) — auto-formats staged `*.swift` and re-stages fixes; **SwiftLint** `--fix` — auto-corrects mechanical violations (vertical whitespace, modifier order, sorted imports, etc.) and re-stages; **SwiftLint** strict on staged files (`[.swiftlint.yml](../.swiftlint.yml)`); merge-conflict marker scan; **large-file** guard (`[scripts/check-large-files.sh](../scripts/check-large-files.sh)`) — rejects any staged file over 1 MiB; **gitleaks** on staged changes |
| **pre-push**   | Refuses pushes to `main`/`gh-pages` (`[scripts/check-push-refs.sh](../scripts/check-push-refs.sh)`); `check_translations.py` and `check_source_strings.py` (repo-wide, under a second). No compile: `make gate` compiles before a push and CI compiles every push. |


`gitleaks` is optional for solo work but strongly recommended once any secrets or API keys exist in the tree.

Local hooks are bypassable (`--no-verify`, a hookless clone, a web-UI merge); CI (§8.4) re-runs the same gates server-side before code reaches `main`.

### 8.3 Manual commands

- `make system` — machine bootstrap: Homebrew packages above, Python 3.9+ and `xcodebuild` checks, `lefthook install` (see `[scripts/system-setup.sh](../scripts/system-setup.sh)`)
- `make build` — bare compile via `[scripts/build.sh](../scripts/build.sh)` for a generic iOS Simulator destination; boots no simulator
- `make gate` — the pre-PR gate (`[scripts/gate.sh](../scripts/gate.sh)`): tool versions, format and lint on changed Swift files, script tests, compile; no simulator
- `make lint` — `swiftlint lint --strict` over the repo
- `make lint-fix` — `swiftlint --fix --quiet .` then `swiftlint lint --strict` (auto-fix + verify)
- `make format` — `swiftformat .` (format everything, not only staged files)
- `make tests` — full unit then UI run on the repo's simulator (CI runs these on every PR; run locally only when needed)
- `make hooks-install` — `lefthook install` (refresh hooks after pulling config changes)



### 8.4 Continuous Integration (GitHub Actions)

CI lives in `.github/workflows/` and re-runs the local gates server-side, where they cannot be bypassed. Branch protection on `main` should **require** the PR checks below (one-time repo-admin setup in Settings → Rules → Rulesets; CI is advisory without it).

This is a public repo, so GitHub-hosted macOS/Simulator runner minutes are free and unbounded; cost does not gate what runs per PR. App Store metadata and screenshot-content correctness are release-time concerns (there can be 100+ PRs between releases), so `check_source_voice.py` and `check_content.py` live in the fastlane `push_metadata`/`screenshots` lanes (`fastlane/Fastfile`, `fastlane/SETUP.md`), not in `ci.yml`.

`ci.yml` — on every `pull_request` and `push` to `main`:


| Job                  | Runner | What                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| -------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lint`               | ubuntu | SwiftFormat `--lint` + SwiftLint `--strict`, **pinned** to the local Homebrew versions (SwiftLint 0.65.1 / SwiftFormat 0.64.1) to avoid CI-vs-local rule drift. Keep these versions in lockstep with local installs. SwiftFormat is a cached release binary; SwiftLint runs from the official `ghcr.io/realm/swiftlint` image (the release zip needs `libxml2.so.2`, missing on Ubuntu 26.04).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `secrets`            | ubuntu | `gitleaks git` over full history — complements pre-commit `gitleaks git --pre-commit --staged`. The version is pinned in `config/lint-tools.env`. Reviewed-and-accepted findings are allowlisted by fingerprint in `.gitleaksignore`. The four retained fingerprints cover pre-externalization commits that hardcoded the Mixpanel project tokens; HEAD does not (values live in gitignored `config/Secrets.local.xcconfig`, over `config/Secrets.xcconfig` base defaults). Keep the `.gitleaksignore` entries: history is not rewritten, so the full-history scan still sees those commits. A release ship guard (`scripts/verify_release_secrets.sh`, called by Fastlane `beta`/`release` lanes and the Xcode Release-only Run Script phase) blocks builds that still carry placeholder sentinels — it is not run in CI, since it checks for a gitignored local secrets file that never exists in a CI checkout. |
| `check-large-files`  | ubuntu | `scripts/check-large-files.sh` against the PR diff (mirrors the pre-commit hook, which only sees staged files locally).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `i18n-gates`         | ubuntu | `check_translations.py`, `check_source_strings.py`, `check_metadata.py` (the pre-push translation gates), plus the deterministic `plural_completeness.py` and `untranslated_copies.py` checks, plus a non-blocking `consistency_check.py --ignore-casing`. Enforces issue #172 server-side. Each mechanical check runs through `scripts/ci/annotate.py`, which turns `--json` findings into GitHub annotations and a step summary; the `summary` job reports each job's result.                                                                                                                                                                                                                                                                                                                |
| `tooling`            | ubuntu | `python3 -m unittest` over `scripts/tests` and `scripts/simulator-slots/tests`: the offline script tests `make gate` runs locally, so CI covers the whole gate and `/merge-pr` runs none of it again. |
| `changes`            | ubuntu | Lists the PR's files (both paths of a rename) and runs `scripts/ci/docs_only.py`: `code=false` only when every file is docs (Markdown outside `scripts/`, or anything under `docs/`, `openspec/`, `releases/`, `.claude/`, `.cursor/`) and none is in an app/test target folder. Pushes to `main`, an empty list, a PR of 3000+ files and any read error give `code=true`. |
| `build`              | macOS  | Runs after the gates and `changes`, unless `changes` says docs-only. Selects Xcode 26.5 (`.github/actions/ios-setup`), restores a SwiftPM cache keyed on `Package.resolved`, and compiles once with `xcodebuild build-for-testing` for any simulator (ad-hoc signed so entitlements embed; on failure `scripts/ci/xcode_errors.py` turns each compile error into a PR annotation and a job-summary line). The products go up as a tarball artifact (`test-products`). |
| `unit-tests`         | macOS  | Downloads the products (`.github/actions/test-products`, which points `XCTESTRUN` at them), then `make unit-tests` serially on one simulator. On failure the `.xcresult` is uploaded. |
| `ui-tests`           | macOS  | A matrix of parallel shards defined in `scripts/ci/ui_shards.py`: `accessibility` (`AccessibilityAuditTests`), `user-journey` (`UserJourneyTests`) and `rest` (every other class in the UI target except the screenshot captures and Xcode template classes: today `ClearAmountButtonUITests` and `AllocationFirstTapUITests`), balanced by suite time. Same setup as `unit-tests`; each shard runs `make ui-tests UI_SHARD=<name>` with `UI_WORKERS=1` and `UI_RETRY_ON_FAILURE=1`, the same selection as locally. |
| `focused-tests`      | macOS  | Manual runs only (`test` input): `make focused-tests` on one class or test, `iterations` times, with the same setup as `unit-tests`. |
| `tests`              | ubuntu | The required check. Passes when every build and test job the run asked for passed (by default `build`, `unit-tests` and every `ui-tests` shard), or when `changes` found a docs-only PR and all three were skipped; anything else fails. Shards can be added or renamed without touching the ruleset. |
| `summary`            | ubuntu | Every run: writes the job summary page and, via `scripts/ci/ci_summary.py`, a PR comment (a PR push edits one comment in place; a `/ci` run or a push to `main` posts a new one). Informational only — not a required status check. |


The account runs at most 5 macOS jobs at once across all its repos; a full run holds 4 (the `build`, then `unit-tests` plus 3 shards). The macOS test jobs run the same Makefile targets as local work (`make unit-tests`, `make ui-tests UI_SHARD=…`, `make focused-tests`) through the per-checkout simulator sandbox, with `XCTESTRUN` pointing at the `build` job's products so they build nothing. Locally `UI_WORKERS` (1..3) sets how many simulators the UI pass uses; CI uses 1. The maintainer's machine-wide simulator-slots pool (AGENTS.md § Simulator slots) is off on runners, which have no pool master. Xcode is pinned to 26.5.

`ci-command.yml` — comment `/ci ...` on a PR (`/ci help` lists the words; documented in `.github/pull_request_template.md`) to dispatch `ci.yml` on the PR branch with a chosen set of gates and tests, e.g. `/ci ui` for the UI suite or `/ci test <target>/<Class>[/<test>] x3` to repeat one class or test. The parser is `scripts/ci/ci_command.py`. Only the repo owner's comments start runs. `issue_comment` workflows always run the default-branch copy of the file, so trigger changes take effect only after merging to `main`.

`dependabot.yml` — weekly `github-actions` updates only. The SPM deps (`mixpanel-swift`, `mixpanel-swift-common`, `json-logic-swift`) are **not** Dependabot-trackable because the app has no `Package.swift` (deps are Xcode-project-managed); SPM bumps are manual.

---



## 9. Future Technical Considerations

Backlog items that need technical design when prioritized.

> ⚠️ **Any change that introduces an app extension target** (widget, Live Activity, Lock Screen widget, Control Center widget, App Clip, Share / Action / Intents / Notification Service extension) SHALL first read [§4.7 Multi-process / extension considerations](#47-multi-process--extension-considerations--read-before-shipping-any-extension-target). The store is single-process today; the cross-process SwiftData `ModelContainer` migration race is a known production-crash class and must be mitigated in the same change that ships the extension.


| Feature                                                                 | Technical Surface                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **F-4.01–02: Color themes**                                             | Asset Catalog color sets, theme state in `NSUbiquitousKeyValueStore` (synced via iCloud) or SwiftData, `@Environment(\.colorScheme)` integration                                                                                                                    |
| **F-6.02: Expense Type**                                                | Schema done: `expenseType: String?` on `ExpenseItem`. Remaining: user-facing editor, user-defined values stored as a `Set<String>` in `NSUbiquitousKeyValueStore` (synced via iCloud) or a dedicated entity.                                                        |
| ~~**F-6.03: App Store rating prompt**~~ ✓ Implemented (`rating-prompt`) | `RatingPromptCoordinator` + KV-backed `RatingPromptState` (§4.5 `ratingPrompt`* keys); Add-mode expense-save trigger hook; root `ratingPromptPresenter()` calls the native `requestReview`. Cooldown is platform-managed (Apple throttle + once-per-version guard). |
| **F-7.01: Receipt scanning**                                            | Vision framework (`VNRecognizeTextRequest`), on-device OCR, regex extraction for amounts                                                                                                                                                                            |
| **F-7.02–03: Voice input/query**                                        | SiriKit intents or App Intents framework, on-device NLP, `SFSpeechRecognizer` for in-app voice                                                                                                                                                                      |
| **F-8.03: Mixpanel Phase 2**                                            | React to Phase 1 evidence; add experimentation seam; extend event coverage per `docs/analytics-spec.md` §§12–15. Operationalized in `docs/analytics-spec.md` §4 / §12–15.                                                                                           |


**Shipped (removed from future table):** F-4.03 budget emoji icons, F-5.01 week start, F-6.01 add funds, F-7.04–07 recents / lifecycle dates / pause-resume, F-8.01–02 OSLog + Mixpanel Phase 1.

---



## 10. Decision Log


| #   | Decision | Rationale |
| --- | -------- | --------- |


---



## Appendix



### A. Glossary

See [main-prd.md §10.1](main-prd.md#101-glossary) for product terms. Technical terms used in this document:

- `@Model` — SwiftData macro that marks a class as a persistent model.
- `@Observable` — Swift macro for observation-tracked reference types (replaces `ObservableObject`).
- `@Query` — SwiftData property wrapper for reactive data fetching in SwiftUI views.
- `ModelContainer` — SwiftData object that manages the schema, storage, and sync configuration.
- **CKRecord** — CloudKit's record type; SwiftData models map to CKRecords when CloudKit sync is enabled.



### B. Revision History


| Version | Date       | Author   | Changes                                                                                                                                                                                                                                                                                                                                |
| ------- | ---------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0    | 2026-07-26 | Jimmy Ho | Updated doc to v1.0 to coincide with the v1.0 App Store release. §3.3 Migration Strategy rewritten for post-launch reality: v1.0 shipped 2026-07-22 and the CloudKit production schema deployed 2026-07-12, so `SchemaV1` is a frozen deployed baseline. Any persisted-model change now requires a new `VersionedSchema`, a `MigrationStage`, a migration test (`MigrationTestSupport` pattern), and additive-only fields. Removed the pre-1.0 "greenfield / edit in place / wipe the simulator" guidance. |
| 0.24    | 2026-06-11 | Jimmy Ho | Docs-vs-code audit fixes: §2.2 route case signatures corrected to UUID payloads (`budgetDetail(UUID)`, `editBudget(UUID)`, `addExpense(UUID)`) and `SheetRoute.analyticsConsent` added to the case list; §5.3 `UserJourneyTests` count 10 → 15 (reorder-budgets + 4 period-chip flows).                                                |
| 0.23    | 2026-06-02 | Jimmy Ho | Rebrand doc sync: intro and §1 use Wren as product name; §5.1 proper-noun list adds Wren.                                                                                                                                                                                                                                              |
| 0.22    | 2026-06-02 | Jimmy Ho | §4.5 KV-key table: add six `ratingPrompt*` keys (owner `RatingPromptState`, consent-independent) for F-6.03. §9 future table: mark F-6.03 implemented (`rating-prompt`). See `product-features-planning.md` F-6.03 and `analytics-spec.md` §12.                                                                                        |
| 0.21    | 2026-06-01 | Jimmy Ho | §5.3: rewrite testing section — two-pass UI script strategy, `UserJourneyTests` (10 flows, XCTestCase), `AccessibilityAuditTests` runs in pass 2 (not excluded), screen objects, `make test-ui`. Note that Swift Testing is not supported in XCUITest targets.                                                                         |
| 0.20    | 2026-05-31 | Jimmy Ho | §5.3 add accessibility-audit test note: `AccessibilityAuditTests.swift`, `performAccessibilityAudit()`, excluded from `make test`.                                                                                                                                                                                                     |
| 0.19    | 2026-05-31 | Jimmy Ho | Doc/code sync: §4.2 CloudKit container ID set in entitlements; §2.1 documents `AddEditBudgetViewModel` / `AddEditExpenseViewModel`; §3.1 `Budget.icon`; §5.4 `recomputeToken` refresh + `specificDatesBranch` pointer; §7 network surface (Mixpanel + CloudKit, no app backend); §9 future table refreshed (shipped features removed). |
| 0.18    | 2026-05-03 | Jimmy Ho | §4.5 KV-key table: add `analyticsOptIn`, `analyticsDistinctId`, and `analyticsFirstOpenAt` rows (F-8.02). §7 product-analytics paragraph: document lazy Mixpanel SDK init, consent toggle wiring, and PII contract; update §16.1 reference to historical. §9 future table: add F-8.03 Phase 2 row.                                     |
| 0.17    | 2026-05-02 | Jimmy Ho | §7 expanded the on-device diagnostics entry: canonical call-site map for `bootstrap`, `cloudkit`, and `ui` categories; explicit `privacy:` annotation rule; cross-reference to `docs/analytics-spec.md` §17 for the OSLog ↔ `AnalyticsClient` boundary. (F-8.01 implemented by change `oslog-diagnostic-logging`.)                     |
| 0.16    | 2026-05-02 | Jimmy Ho | §7 expanded the product-analytics paragraph to call out Mixpanel SDK lazy init, the canonical client-selection table, and cross-references to `docs/analytics-spec.md` §§8 / 8.1 (ordering) and §16.1 (implementation starting state) ahead of F-8.01 / F-8.02 OpenSpec planning.                                                      |
| 0.15    | 2026-04-30 | Jimmy Ho | §5.1 add `Text(verbatim:)` rule for locale-invariant strings (app version + build, raw ISO codes, etc.) so they are not auto-extracted into the catalog as opaque `%@`-format keys; pair with a localized `accessibilityLabel` when the row exposes translatable copy via VoiceOver.                                                   |
| 0.14    | 2026-04-30 | Jimmy Ho | Loc + VoiceOver audit conventions: §5.1 add shared-key (`common.*`) policy; §5.2 codify single-element composite a11y, header rotor trait, destructive hint requirement, and `swipeActions` ↔ `accessibilityAction` pairing rule. Cross-link audit at `docs/audits/localization+voiceover-audit-2026-04-30.md`.                        |
| 0.13    | 2026-04-30 | Jimmy Ho | Continued drift audit (phase 2): §3.2 fix broken anchor link (67-overunder → 67-carry-over); §5.5 document color-literal exceptions (money, sync status, destructive tints); §9 mark F-5.01 as shipped, update F-6.01/F-6.02 partial-impl notes                                                                                        |
| 0.12    | 2026-04-30 | Jimmy Ho | Doc/code drift audit: §2.2 fix Router ownership (app entry point, not RootView); §8.2 fix pre-push to reference `scripts/build.sh` + `_destination.sh`; §8.3 add `make build`, `make lint-fix`, `make hooks-install`                                                                                                                   |
| 0.11    | 2026-04-29 | Jimmy Ho | §2.1: list `BudgetDetailView` as a View+Services example with its three lifecycle-refresh triggers; §5.1: document count-driven plural variation pattern and inline vs list-label period-name rule                                                                                                                                     |
| 0.10    | 2026-04-29 | Jimmy Ho | §8: `make system` / `scripts/system-setup.sh`; clarify Python 3 for `make test` vs Lefthook; optional OpenSpec CLI note                                                                                                                                                                                                                |
| 0.9     | 2026-04-29 | Jimmy Ho | Add §8 Developer Tooling (Lefthook, SwiftLint, SwiftFormat, gitleaks, large-file script, Makefile targets); renumber former §8–§9 to §9–§10                                                                                                                                                                                            |
| 0.1     | 2026-04-10 | Jimmy Ho | Initial draft                                                                                                                                                                                                                                                                                                                          |
| 0.2     | 2026-04-11 | Jimmy Ho | Add §4.5 (NSUbiquitousKeyValueStore for app settings); update §8 future table to reflect iCloud key-value store instead of UserDefaults                                                                                                                                                                                                |
| 0.3     | 2026-04-13 | Jimmy Ho | Add §5.4 documenting the `PeriodCalculator` / `BudgetCalculator` service layer (public API, biweekly anchor convention, ViewModel consumption pattern)                                                                                                                                                                                 |
| 0.4     | 2026-04-17 | Jimmy Ho | Update §5.4 to add `BudgetLifecycleService` as the sole orchestrator of the eager roll → persist → reset → persist sequence; clarify ViewModel consumption contract                                                                                                                                                                    |
| 0.5     | 2026-04-17 | Jimmy Ho | Add §4.6 (`FirstRunSeeder`, two-gate decision, `"seededV1"` KV key, flag-write ordering); add KV key table to §4.5; add §5.5 Bootstrap                                                                                                                                                                                                 |
| 0.6     | 2026-04-28 | Jimmy Ho | Add `"currencyDisplay"` KV-key row to §4.5 table; document `SyncStatus` environment value plumbing (containerBacking, accountStatus, rowState) in §4.5                                                                                                                                                                                 |
| 0.6     | 2026-04-17 | Jimmy Ho | Replace §2.1 MVVM framing with "View + Services, ViewModels on demand" (escalation criteria, VM rules, grey-area ping protocol); update §5.4 consumer wording to "screens (and any VMs)"                                                                                                                                               |
| 0.7     | 2026-04-24 | Jimmy Ho | Remove §4.6 (FirstRunSeeder) and §5.5 (Bootstrap); drop `"seededV1"` from §4.5 KV key table; add orphaned-key note; see change `remove-first-run-seeder`                                                                                                                                                                               |
| 0.8     | 2026-04-26 | Jimmy Ho | Add §5.5 (Color Palette and Theming): `AppBackground`/`CellBackground` asset definitions, `appBackground()` modifier usage pattern, list screen wiring, and future theming notes                                                                                                                                                       |


