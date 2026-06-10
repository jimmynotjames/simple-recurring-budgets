# Technical Design Document

| Field              | Value                          |
| ------------------ | ------------------------------ |
| **Version**        | 0.23                           |
| **Last Updated**   | 2026-06-02                     |
| **Author / Owner** | Jimmy Ho                       |

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

**Default:** Screens are SwiftUI Views that read data with `@Query`, write through `@Environment(\.modelContext)`, and delegate non-trivial logic to pure domain services in `Domain/` (`BudgetLifecycleService`, `BudgetCalculator`, `PeriodCalculator`). No companion ViewModel is introduced by default.

**Why not a VM on every screen.** The `Domain/` layer already carries the testable business logic as pure, SwiftData-free services (see §5.4). Adding a VM to thin list or detail screens mostly relays calls, duplicates state, and introduces lifecycle plumbing (`ModelContext` injection, `bind` timing, preview setup) without a payoff. Keeping reads in the view via `@Query` also preserves SwiftUI's automatic invalidation on SwiftData changes — something a VM-held fetch would have to reimplement.

**Escalate to an `@Observable` ViewModel only when at least one of these is true:**

1. The screen holds **non-trivial draft/form state** not persisted until the user commits (e.g., an Add/Edit screen with cross-field validation).
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
- A single user input that mutates more than one model property or couples fields.
- The screen is expected to grow materially within the next 1–2 features.

Pure display-only subviews (row cells, badges, amount formatters) remain logic-free regardless of which side of the rule the parent screen falls on.

**Implemented View + Services screens:**

- `BudgetsView` — root list; `@Query` drives the row list; `BudgetLifecycleService.result(for:)` called from each row's `.task(id:)`, `onChange(of: scenePhase)`, and `onChange(of: budget.recomputeToken)`.
- `BudgetDetailView` — Budget detail; lifecycle refresh invoked from `.task(id: budget.persistentModelID)`, `onChange(of: scenePhase)`, and `onChange(of: budget.recomputeToken)`. Destructive actions are short imperative methods on the view that write through `@Environment(\.modelContext)` and call `BudgetLifecycleService` afterward.

**Escalated ViewModel screens (draft/form state):**

- `AddEditBudgetViewModel` — Add/Edit Budget sheet: cross-field validation, orphan-expense warning, allocation/start/end save paths, and `budget_edited` analytics property flags.
- `AddEditExpenseViewModel` — Add/Edit Expense: date-bounds validation, Add Funds toggle + sign-on-save, recents candidates (F-7.04).

### 2.2 Navigation: `NavigationStack` with value-based routing

The app's information architecture is a simple stack: Budgets list → Budget detail → Expense detail. A `NavigationStack` with a `Hashable` route enum and `navigationDestination(for:)` handles this cleanly — type-safe, state-driven, and deep-linkable. iPad/Mac can use adaptive layout without requiring a full split view.

Route enums (`AppRoute`, `SheetRoute`) carry the model's stable `id` (`UUID`), never a live model reference, so routes stay serializable for future deep links, widgets, and App Intents. `RootView` resolves the UUID at the destination via `ModelContext.budget(id:)` / `.expenseItem(id:)` (`Models/ModelContext+Lookup.swift`); an unresolvable ID — the model was deleted (e.g., on another device) after the route was set — silently pops the push or dismisses the sheet.

A small `@Observable Router` (`path: [AppRoute]`, `sheet: SheetRoute?`) is owned by the app entry point (`simple_recurring_budgetsApp`) as `@State` and injected into the SwiftUI environment via `.environment(router)`. `RootView` and all descendant screens access it via `@Environment(Router.self)` so leaf screens trigger pushes and sheets without holding navigation state themselves.

`AppRoute` push cases: `budgetDetail(Budget)` (Budgets list → Budget detail), `expenseDetail(ExpenseItem)` (Budget detail → Expense edit, F-2.04 edit path). `SheetRoute` sheet cases: `addBudget`, `editBudget(Budget)`, `addExpense(Budget)`, `settings`. Existing-expense editing is reached via push (`AppRoute.expenseDetail`), not a sheet.

`AddEditExpenseView` does not own a `NavigationStack`; the navigation context is provided by the caller. For the sheet path (`addExpense`), `RootView` wraps it in `NavigationStack { }`. For the push path (`expenseDetail`), the outer `NavigationStack` in `RootView` provides the context directly.

---

## 3. Data Model

### 3.1 Approach

Four SwiftData `@Model` entities: **Budget**, **ExpenseItem**, **AllocationChange**, and **LifecycleEvent**, all held in `SchemaV1`. `Budget → ExpenseItem`, `Budget → AllocationChange`, and `Budget → LifecycleEvent` are all cascade-delete one-to-many relationships. Supporting enums (`BudgetPeriod`, `LifecycleEventKind`) are `String`-backed `Codable` types stored on entities as raw `String` columns with typed computed accessors — this keeps the columns visible to `#Predicate` queries (Codable-backed enum storage would be opaque to predicates).

The user-facing entry point for deleting a `Budget` is the **Delete Budget** button on the Add/Edit Budget sheet (Edit mode only). Confirming the dialog calls `context.delete(budget)` + `context.save()` on `AddEditBudgetViewModel`; the `@Relationship(deleteRule: .cascade)` rules automatically removes the budget's `ExpenseItem`, `AllocationChange`, and `LifecycleEvent` rows in the same save. No schema or CKRecord change is involved.

**CloudKit optional relationship pattern:** CloudKit requires all relationships to be optional (records may arrive out-of-order during sync). All stored relationship properties (`Budget.expenses`, `Budget.allocationChangesStorage`, `Budget.lifecycleEventsStorage`, `ExpenseItem.budget`, `AllocationChange.budget`, `LifecycleEvent.budget`) are therefore typed optional. Non-optional computed accessors (`expenseItems`, `allocationChanges`, `lifecycleEvents`) returning `?? []` are the canonical accessors for all app code.

**Budget entity fields:**

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Stable identity |
| `name` | `String` | Display name |
| `currencyCode` | `String` | ISO 4217 code |
| `period` | `String` | `BudgetPeriod.rawValue` |
| `sortOrder` | `Int` | User-defined list ordering |
| `createdAt` | `Date` | Immutable after creation |
| `lastModified` | `Date` | Bumped on every user-initiated mutation that affects math |
| `startDate` | `Date?` | When the budget begins; semantically always populated for saved budgets (CloudKit optionality only) |
| `endDate` | `Date?` | Terminal cutoff; `nil` for open-ended recurring budgets |
| `lastResetDate` | `Date?` | Most recent manual Reset Carry-Over or Reset Budget timestamp; `nil` means no reset |
| `isCarryOverEnabled` | `Bool` | Display toggle; algorithm always computes carry-over internally |
| `icon` | `String?` | Optional emoji budget icon (F-4.03); `nil` when unset |
| `allocationChangesStorage` | `[AllocationChange]?` | Allocation history; use `allocationChanges` computed accessor |
| `lifecycleEventsStorage` | `[LifecycleEvent]?` | Pause/resume history; use `lifecycleEvents` computed accessor |
| `expenses` | `[ExpenseItem]?` | Expense rows; use `expenseItems` computed accessor |

**AllocationChange entity fields:** `id`, `effectiveFrom: Date`, `amount: Decimal`, `lastModified: Date`, `budget: Budget?`.
**LifecycleEvent entity fields:** `id`, `kindRawValue: String` (raw value of `LifecycleEventKind`; exposed via a typed `kind` accessor — storing the raw string preserves `#Predicate` filter compatibility), `effectiveDate: Date`, `lastModified: Date`, `budget: Budget?`.
**ExpenseItem entity fields:** `id`, `amount: Decimal` (signed; negative = add-funds), `name: String?`, `date: Date`, `createdAt: Date`, `lastModified: Date`, `expenseType: String?`, `budget: Budget?`.

All monetary values use `Decimal`, never floating-point.

Derived values — **Remaining for current Budget Period** and **Carry-over** — are computed at read-time via `BudgetCalculator.snapshot(...)` and never persisted.

### 3.2 Carry-Over Bookkeeping

Per [PRD §6.7](main-prd.md#67-carry-over-behavior), the algorithm is a **live walker** (no stored carry-over amount):

- **`BudgetCalculator.snapshot(budget:expenses:now:calendar:)`** is the single pure read entry point. It is stateless and never mutates the budget.
- The walker sums `(allocationInEffect(at: periodStart) − expenses)` for every completed active period in the window `[max(startDate, lastResetDate ?? .distantPast), currentPeriodStart)`.
- The **asymmetric live coupling rule** adds the current period's *committed* overflow — overspend and add-funds excess — to the walker sum in real time. Ordinary mid-period slack waits for the period close.
- **Manual reset**: `BudgetLifecycleService.resetCarryOver(_:context:)` sets `lastResetDate = now`, trimming the walker window so carry-over reads zero from that moment forward.

### 3.3 Migration Strategy

This app has not shipped to the App Store — it is greenfield. Schema changes are made in-place on `SchemaV1`. Do **not** introduce `SchemaV2` or `SchemaMigrationPlan` stages; wipe the simulator when the schema changes. Always test CloudKit compatibility — CloudKit cannot delete fields from deployed record types.

---

## 4. Persistence and Sync

### 4.1 SwiftData + CloudKit

SwiftData persistence with `cloudKitDatabase: .automatic` on `ModelConfiguration` enables CloudKit sync with the default container. This is the simplest integration path for SwiftData-backed CloudKit apps.

**Single-store guarantee (split-brain prevention).** `makeProductionModelContainer` tries a CloudKit-enabled config first and falls back to a local-only (`cloudKitDatabase: .none`) config when iCloud is unavailable (offline / not signed in). Both configs are pinned to one shared on-disk store `url`, obtained from `ModelConfiguration(schema:isStoredInMemoryOnly:false).url` (SwiftData's own default path, so existing installs keep their current store). Pinning the URL guarantees the two configs can never resolve to different files: an offline first launch writes to the store, and a later online launch opens that **same** store and attaches CloudKit mirroring in place — the local data is promoted to the cloud rather than stranded in a forked, empty store. The `PersistentStoreURLTests` lock in the invariant that a config's `url` is independent of its `cloudKitDatabase` setting.

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
| `"analyticsOptIn"` | `Bool` | `AppSettings` | User's analytics opt-in preference. Written only on first explicit user action; absent key means "not yet decided". Default is locale-aware (`ConsentJurisdiction`): `.required` regions default to `false`; `.autoOptin` regions default to `true`. See `docs/analytics-spec.md` §7. |
| `"analyticsDistinctId"` | `String` (UUIDv4) | `AppSettings` | Stable Mixpanel distinct ID generated on first read and synced via iCloud KV. Read-only after creation. See `docs/analytics-spec.md` §6. |
| `"analyticsFirstOpenAt"` | `Double` (seconds since epoch, `Date.timeIntervalSinceReferenceDate`) | `AppSettings` | Timestamp of first app open, generated on first read. Used for `time_since_first_app_open_bucket` super-property. See `docs/analytics-spec.md` §10.2. |
| `"ratingPromptInstalledAt"` | `String` (`Date.timeIntervalSinceReferenceDate`) | `RatingPromptState` | First-launch timestamp for the F-6.03 rating prompt, stamped once. **Not** analytics-gated — distinct from `analyticsFirstOpenAt`. |
| `"ratingPromptLoggedExpenseCount"` | `Int64` | `RatingPromptState` | Lifetime count of successful Add-mode expense logs (F-6.03 eligibility). |
| `"ratingPromptDistinctLogDayCount"` | `Int64` | `RatingPromptState` | Count of distinct calendar days an expense was logged (F-6.03 eligibility). |
| `"ratingPromptLastLogDayStart"` | `String` (`Date.timeIntervalSinceReferenceDate`) | `RatingPromptState` | Start-of-day of the most recent logging day; detects a new distinct day. |
| `"ratingPromptFirstEligibleAt"` | `String` (`Date.timeIntervalSinceReferenceDate`) | `RatingPromptState` | When the rating thresholds were first met; one-shot gate for `rating_prompt_eligible`. |
| `"ratingPromptLastRequestedVersion"` | `String` (`CFBundleShortVersionString`) | `RatingPromptState` | App version a review was last requested for; the once-per-version guard (F-6.03). |

> **Orphaned key:** The string `"seededV1"` was used by a prior first-run seeder (removed in change `remove-first-run-seeder`) and is now a harmless leftover on upgraded installs. It SHALL NOT be reused as a new KV key; the `"V1"` suffix remains reserved per convention so any future one-time-reseed change introduces a distinct key name (e.g., `"seededV2"`).

**SyncStatus environment value:** `SyncStatus` is an `@Observable final class` injected into the SwiftUI environment via `.environment(syncStatus)` in `simple_recurring_budgetsApp`. It carries two properties: `containerBacking: ContainerBacking` (`.cloudKit` or `.localFallback`), which is determined once at launch from the outcome of `makeProductionModelContainer` and never mutated; and `accountStatus: AccountStatus` (`.checking`, `.available`, or `.unavailable`), which is updated asynchronously by `SettingsView` via `CKContainer.default().accountStatus()` and live `CKAccountChanged` / `NSUbiquityIdentityDidChange` notification observers. A derived `rowState: RowState` property combines both fields to produce the four-state view-state for the Settings iCloud row (`.checking`, `.available`, `.paused`, `.unavailable`). Screens consume it via `@Environment(SyncStatus.self) private var syncStatus`.

### 4.6 Container creation recovery (no `fatalError`)

`makeProductionModelContainer` is a throwing function. When both CloudKit-backed and local-only `ModelContainer` creation fail, the error is surfaced to the `@Observable AppStartup` model (`simple-recurring-budgets/App/AppStartup.swift`) and the `@main` body presents `ContainerFailureView` (Retry + Send Feedback) instead of crashing — see the `container-creation-recovery` capability. The `Logger.cloudKit.error("cloudkit.container.failed: …")` line still fires before the throw per the `diagnostic-logging` capability.

Realistic causes of a both-paths failure in production (community-reported, ordered by likelihood for this app):

1. **Disk full** (`NSFileWriteOutOfSpaceError` / Cocoa 640). SQLite's WAL/journal can't grow. Retry won't help until the user frees space.
2. **Schema migration failure.** A future `BudgetMigrationPlan` step throwing — bad mapping, version-mismatch, or a failing `MigrationStage`. Retry occasionally succeeds (transient pressure releases). The recovery path of last resort is to wipe the store; we do not do this automatically.
3. **Migration race condition between the app and any future extension** — see §4.7 below.
4. **Corrupted SQLite store.** Power-loss mid-WAL-checkpoint, OS-update artifact. Retry rarely helps; Send Feedback is the escape hatch.
5. **CloudKit account in transit.** User just signed out / switched Apple IDs / mid-mirror recovery. Often self-resolves on the next launch; Retry is a clean win here.

### 4.7 Multi-process / extension considerations — **read before shipping any extension target**

⚠️ **This app currently has no app extension targets** (no widget, no Live Activity, no Lock Screen widget, no Control Center widget, no App Clip, no Share / Action / Intents / Notification Service extension). The container model assumes a **single-process owner** of the on-disk store.

**When a future change introduces any of the above, the following SHALL be re-evaluated in the same change** (the agent adding the extension owns this checklist):

1. **App Group + shared store URL.** Decide whether the extension reads or writes the same SwiftData store. If yes, move the store to a shared App Group container (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`) and update `makeProductionModelContainer` to anchor `ModelConfiguration.url` there instead of the default app-sandbox path. Treat this as a one-shot migration (copy the existing store file once, gated by a `NSUbiquitousKeyValueStore` flag, then read from the new path) — the per-config `url` invariant tested by `PersistentStoreURLTests` extends to the new path.
2. **Migration race condition.** SwiftData / CoreData does **not** serialize `ModelContainer` creation across processes. If the host app and an extension both attempt to open the store during a schema migration (e.g. the user updates the app and the system wakes the widget at the same time), one or both `ModelContainer.init` calls can throw with no useful diagnostic. The community-recommended mitigation is a **process-level lockfile** wrapping the `ModelContainer(...)` call (write a sentinel file in the App Group container; second-comer waits on it with a short timeout). Add this in the same change as the extension; do not ship the extension without it.
3. **Read-only vs read-write split.** If the extension only needs to *read*, prefer giving it a read-only `ModelContainer` (or a snapshot exported to a smaller cache file) so it cannot race with the host's migrations.
4. **Background-launch + file protection.** If the extension can be launched while the device is locked (most widget refreshes can), the store file's data-protection class matters. Default is `NSFileProtectionCompleteUntilFirstUserAuthentication`, which is usually fine; verify before shipping.
5. **Retry semantics with extensions.** `ContainerFailureView.Retry` only re-runs the host app's container creation. If the extension is the one that's wedged, the user has no recovery surface in the extension itself — extensions should fail silently (a stale widget) rather than show their own error UI, and rely on the host-app launch to repair the store.

If the change you're working on is "add a widget" / "add a Live Activity" / "add an App Clip" / "add an Intents extension" / similar, treat the five points above as required reading. Driggers' "All the ways SwiftData's ModelContainer can Error on Creation" (2025) is the canonical community writeup of the race condition.

---

## 5. Internationalization, Accessibility, and Testing

### 5.1 Internationalization

All user-facing text uses Xcode **String Catalogs** and `LocalizedStringKey` — no hard-coded English in production views. Dates and numbers use Foundation format styles that auto-adapt to locale. Each Budget stores its own ISO 4217 currency code; formatting uses `Decimal.FormatStyle.Currency`.

The canonical catalog lives at `simple-recurring-budgets/Resources/Localizable.xcstrings` and is picked up automatically by the app target's `PBXFileSystemSynchronizedRootGroup`; no `project.pbxproj` changes are needed when adding or renaming strings. Every new user-facing string in a production view must use `Text("key", comment: "translator context")` or `LocalizedStringKey("key")`. The `comment:` argument is required whenever the source string would be ambiguous out of context (short labels, button titles, destructive action names, etc.). Placeholder strings in `Views/RootView.swift` are exempt until the real T-2 screens replace them.

**Count-driven plurals** — when copy genuinely varies by count (e.g. "1 item" vs "2 items"), use Xcode String Catalog plural variations (CLDR `one`/`other` per locale) rather than Swift-side word substitution. The Swift call site passes the integer count as an interpolation (`Text("my.key \(count)")`), which resolves to the catalog key `"my.key %lld"`; the catalog encodes locale-specific `one`/`other` (and `few`/`many` where needed) buckets. Prefer rewriting copy to avoid count-driven plurals when a count-free form ("all expenses", "all items") is equally clear — this keeps the catalog simpler and the call site free of runtime arguments.

**Inline vs list-label period names** — `BudgetPeriod.inlineLabel` (`period.daily.inline`, `period.weekly.inline`, `period.biweekly.inline`, `period.monthly.inline`) and `BudgetPeriod.listLabel` are backed by **separate** per-locale keys. Inline forms are **never** derived from list-label forms via `.lowercased()`, ensuring translators control case for each usage context independently.

**Shared keys for repeated copy** — strings that appear identically across multiple surfaces use a single `common.*` catalog key rather than per-surface duplicates. The current shared keys are:

| Key                    | Used by                                                                                                  |
|------------------------|----------------------------------------------------------------------------------------------------------|
| `common.action.cancel` | Reset Budget confirmation, Reset Carry-Over alert, Currency Picker toolbar, and any future Cancel reuse. |

This avoids translation drift (one surface translating "Cancel" differently from another) and keeps the catalog smaller. New shared copy SHOULD be hoisted under `common.*` only when it is genuinely identical in meaning across surfaces; otherwise prefer per-surface keys so translators can choose context-appropriate wording.

**Locale-invariant strings use `Text(verbatim:)`** — content that is purely numeric, code-like, or otherwise not meaningfully translatable (app version + build number, raw ISO currency codes when shown without a localized name, monospaced identifiers, etc.) MUST use `Text(verbatim: "…")` so the literal is **not** auto-extracted into the catalog. Without this, Xcode silently emits opaque catalog keys like `"%@ (%@)"` that translators cannot interpret and that bypass the project's `screen.purpose.detail` naming convention. Where the same row also exposes translatable copy via VoiceOver (e.g. the Settings version row's "Version 1.2.0, build 342" `accessibilityLabel`), localize the **a11y label** with a real catalog key while keeping the visible numerals verbatim.

#### Translation pipeline

Translations for all 49 App Store storefront locales were produced and merged by a four-script pipeline at `scripts/translate_catalog/`:

| Script | Role |
|--------|------|
| `locales.py` | Single source of truth: `LOCALES` list (49 BCP 47 codes) and `LOCALE_NAMES` map |
| `extract.py` | Reads `Localizable.xcstrings`, emits `tmp/translate-inputs/source.json` with English values + format specifier metadata |
| `merge.py` | Reads `tmp/translate-outputs/{locale}.json` per locale; writes `localizations[locale]` back into the catalog with `state: "translated"` and stable sorted-key JSON |
| `validate.py` | Post-merge audit: checks for missing keys, format-specifier multiset equality, non-empty values; exits non-zero on hard errors |

**To add a new key:** write the key in the source view with `String(localized:defaultValue:comment:)`, run `extract.py` to refresh `source.json`, then re-run the translation subagents for that key's values only, then re-run `merge.py` and `validate.py`.

**Model used:** Composer 2 (`composer-2-fast`). The `PROMPT_TEMPLATE.md` in the same directory documents model requirements; if Haiku or another model is available in a future run, swap the slug there.

**Proper nouns kept in English:** "Wren" (product brand), "iCloud", "Carry-Over" (product concept), and App Store brand terms are intentionally left in English for all locales; `validate.py` issues informational warnings (not hard errors) for identical-to-source values.

**App Store listing metadata** is a separate, parallel pipeline at `scripts/translate_metadata/` (driven by the `appstore-translate-metadata` skill / `/appstore:translate-metadata`, gate: `check_metadata.py`). It transcreates the listing copy (`name`, `subtitle`, `keywords`, `promotional_text`, `description`, `release_notes`) from `fastlane/metadata/en-US/` into all 49 storefronts under `fastlane/metadata/<storefront>/`. It is kept distinct from the in-app pipeline because App Store Connect uses *storefront* codes (`de-DE`, `no`, `nl-NL`, `ar-SA`) rather than the app's *runtime* codes; `scripts/translate_metadata/metadata_locales.py` owns the runtime→storefront map. Per-storefront subagents run on Opus (marketing transcreation, not literal translation) and enforce Apple's per-field character limits; the brand "Wren" is a proper noun kept verbatim in every locale (so no localized home-screen icon name is needed). See `scripts/translate_metadata/README.md`.

### 5.2 Accessibility

- **Dynamic Type**: System text styles everywhere; no fixed frame heights that clip at larger sizes.
- **VoiceOver**: Meaningful accessibility labels on all interactive controls; financial amounts include currency context. Custom composite views (carry-over chip, currency picker rows, current-period section header on Budget detail) collapse to a single VoiceOver element via `.accessibilityElement(children: .ignore)` paired with an explicit composed `.accessibilityLabel(...)`. Headings use `.accessibilityAddTraits(.isHeader)` so the VoiceOver headings rotor surfaces them. This applies to `List`/`Section` header `Text` views and semantic content-area headers (e.g. the budget detail status header). It does **not** apply to `GroupBox` card labels — those are visual section labels, not structural heading hierarchy; adding the trait there is noise, not a requirement. Destructive controls (Reset Budget, Reset Carry-Over, Delete Budget, Delete Expense, swipe-to-delete) carry an `.accessibilityHint(...)` describing the irreversible consequence. **`swipeActions` are not auto-exposed to VoiceOver**; every `swipeActions` block MUST be paired with a matching `.accessibilityAction(named:)` so VO users can invoke the action via the rotor. See [docs/audits/localization+voiceover-audit-2026-04-30.md](audits/localization+voiceover-audit-2026-04-30.md) for the per-screen audit baseline.
- **Dark Mode**: Semantic system colors and Asset Catalog color sets with light/dark variants; no hard-coded color literals.

### 5.3 Testing

**Swift Testing** for all new unit tests. XCUITest targets use XCTestCase — Apple does not support `import Testing` in unhosted UI test bundles. In-memory `ModelContainer` for all automated data tests to ensure isolation. Business logic (budget math, Over/Under rolls, date boundaries) lives in pure, testable services with minimal or no SwiftData/UI dependencies.

**Test Runs**: One iPhone simulator, latest OS. No need to run multiple device models or OS versions unless a test is device-specific.

**Two-pass UI test strategy** (`scripts/test.sh`): Unit tests run first (`-skip-testing:simple-recurring-budgetsUITests`) to warm the simulator — XCUITest requires the sim to have hosted at least one app lifecycle before its IPC socket is reliable. Pass 2 then runs the two XCUITest classes with `-only-testing`:

- **`AccessibilityAuditTests`** — 30 tests using `XCUIApplication.performAccessibilityAudit()` (Xcode 15+) to verify VoiceOver labels, touch-target sizes, Dynamic Type adoption, and text clipping across every major screen.
- **`UserJourneyTests`** — 10 end-to-end flow tests (create budget, navigate to detail, add expense ×2, edit budget, pause/resume, delete/edit expense, delete budget, settings round-trip). Uses XCTestCase with `continueAfterFailure = false`.

Five **screen objects** (`BudgetsScreen`, `BudgetDetailScreen`, `AddBudgetScreen`, `AddExpenseScreen`, `SettingsScreen`) in `simple-recurring-budgetsUITests/` encapsulate element queries. When view labels or navigation change, update the matching screen object. `make test-ui` runs only the UI pass (no unit re-run), useful when iterating on failures.

### 5.4 Budget Math Service Layer

Services in `Domain/` implement all budget math with no SwiftUI dependencies:

- **`PeriodCalculator`** — Pure date math: computes period start/end dates and enumerates period boundaries. Accepts `RecurringBudgetPeriod` (excludes `.specificDates` at compile time). All methods take an injected `Calendar`. Weekly/biweekly anchoring derives from `Budget.startDate`, not `AppSettings.weekStartDay` (which only seeds the pre-populated value at budget creation time).
- **`BudgetCalculator.snapshot(budget:expenses:now:calendar:) -> BudgetSnapshot`** — The single pure read entry point. Stateless; never mutates anything. Computes carry-over via `walkCarryOver(...)` (live walker over completed active prior periods), adds the asymmetric `currentPeriodSpillover(...)` for the in-progress period, and looks up allocation history via `allocationInEffect(at:history:)`. A dedicated **`specificDatesBranch`** handles one-window trip budgets. **Two classifiers split math from UI** (see F-7.06): `isActive(periodStart:periodEnd:sortedLifecycleEvents:)` is period-granular and drives the carry-over walker and the `remaining = 0` short-circuit for fully-paused periods; `isPausedAtMoment(now:sortedLifecycleEvents:)` is moment-granular and drives `BudgetSnapshot.lifecycleState`, flipping `.paused` immediately when a `.pause` event's `effectiveDate` is reached. Returns a `BudgetSnapshot` containing `lifecycleState`, `effectiveAllocation`, `remaining`, `carryOver` (`nil` for `.specificDates`), `effectivePeriodStart`, `effectivePeriodEnd`. Algorithm details: [`docs/budget-calculations-rewrite-algorithm.md`](budget-calculations-rewrite-algorithm.md).
- **`BudgetLifecycleService`** — Compatibility adapter between `BudgetCalculator.snapshot` and the existing view-layer `BudgetLifecycleResult` contract. `result(for:)` is a pure read (calls `snapshot`, maps result, takes no `ModelContext`). Five write-path methods mutate state and `context.save()`: `applyAllocationEdit(_:newAmount:context:)` (insert-or-mutate `AllocationChange`), `resetCarryOver(_:context:)` (sets `lastResetDate`), `resetBudget(_:context:)` (deletes all expenses + sets `lastResetDate`), `pauseBudget(_:context:now:) -> Bool` (inserts `LifecycleEvent(.pause)` if eligible; rejects for `.specificDates`, already paused, or past `endDate`), `resumeBudget(_:context:now:) -> Bool` (inserts `LifecycleEvent(.resume)` if eligible; same rejections). All write-path methods bump `Budget.lastModified = now` before saving.

**Refresh trigger:** Every user-initiated write (expense add/edit/delete, allocation edit, pause/resume, manual reset) bumps `Budget.lastModified = now` in the same `context.save()`. Views also observe **`budget.recomputeToken`** (derived from `lastModified`, expense count, and lifecycle/allocation child timestamps — see `Budget+RecomputeToken.swift`) so chip refresh covers expense edits and CloudKit merges that do not re-bump `lastModified`. Refresh is additionally driven by `.task(id:)` and `onChange(of: scenePhase == .active)`.

**Biweekly anchor:** The cycle anchor for weekly/biweekly periods is `Budget.startDate`. `AppSettings.weekStartDay` seeds the pre-populated value in the Add Budget form; it is not consulted by the algorithm.

**Caller consumption:** Screens call `BudgetLifecycleService.result(for:)` eagerly and bind the returned `BudgetLifecycleResult` to the view. Screens do **not** call `BudgetCalculator.snapshot(...)` directly — `BudgetLifecycleService` is the read-path entry point.

### 5.5 Color Palette and Theming

The app uses a warm earth-tone palette defined as named color assets in `Resources/Assets.xcassets`, with separate light and dark appearances. All views must use these named assets — never hard-coded color literals.

**Exceptions:** Semantic system colors are used for money signals (`Color.moneySurplus` / `Color.moneyDeficit` defined as extensions on `Color` in `Views/Shared/Color+Money.swift`), iCloud sync-status icons (system `.green` / `.orange`), and destructive button tints (`.tint(.red)`). These adapt to light/dark mode via the system palette and do not need custom asset catalog slots. If a future theme change (F-4.01–02) needs per-theme control over these, they can be promoted to named assets at that time.

#### Color assets

Exact values are defined in `Resources/Assets.xcassets` with separate light and dark appearances. The table below documents semantic intent only.

| Asset name | Semantic role |
|---|---|
| `AppBackground` | Screen/page background; fills behind nav bar, list, and empty states |
| `CellBackground` | List row background |
| `AccentColor` | Tint for toolbar icons, text links, toggle tint, foreground accent text, icon-picker selection stroke |
| `AccentFill` | Solid accent backgrounds behind white text (period chips, `.borderedProminent` buttons) |

**Generated symbols:** Xcode emits `Color.accentFill` from the `AccentFill` asset (`GeneratedAssetSymbols`). Use `AccentColor` (or `.accentColor`) for tints and foreground accents; use `Color.accentFill` (`.tint(Color.accentFill)`) for filled controls that render white labels on a sage background. WCAG contrast is met by default in the light/dark asset values — not via `contrast: increased` catalog appearances.

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
- **Network surface**: The app has **no app-owned backend**. CloudKit sync is managed by the OS. The only third-party network client is **Mixpanel** (product analytics), gated by user consent — see §7 product-analytics paragraph and `docs/analytics-spec.md`. All other release traffic is Apple framework traffic (CloudKit, iCloud KV).
- **On-device diagnostics**: Uses Apple's unified logging (`OSLog`) directly via `Logger` constants in `AppLoggers.swift` (categories: `bootstrap`, `cloudkit`, `ui`, `persistence`). These are the canonical four categories; any addition or rename requires a matching update to this section and to the `diagnostic-logging` capability spec. Canonical call-site map: `Logger.bootstrap` — one `info` entry per launch recording the resolved `AppDatabaseLaunchMode`; `Logger.cloudKit` — existing container-backing entries in `makeProductionModelContainer` plus one `notice` entry per iCloud account-status transition in `SettingsView`; `Logger.ui` — one `debug` entry per user-initiated destructive action (`resetBudget`, `resetCarryOver`, `deleteBudget`, `deleteExpense`), recording the entity's `persistentModelID` at `privacy: .private`; `Logger.persistence` — one `error` entry per SwiftData `context.save()` failure surfaced through the shared persistence-save helper (`ModelContext.saveChanges(operation:analytics:)`), interpolating the `PersistenceOperation` identifier and the underlying `NSError`'s `localizedDescription` at `privacy: .public` (both non-user-derived). Every interpolated value at a `Logger.*` call site carries an explicit `privacy:` argument. Diagnostic call sites write to these loggers directly — they never pass through `AnalyticsClient`. The one narrowly-scoped exception (the `persistence_save_failed` sibling event) is codified in [`docs/analytics-spec.md` §17](analytics-spec.md#17-boundary-with-f-801-oslog). Logs stay on device and are not transmitted.
- **Product analytics**: The `AnalyticsClient` protocol is product-only (no diagnostic routing). The default implementation (`ConsoleAnalyticsClient`) prints events in **Debug builds** only (`#if DEBUG`); release builds are silent no-ops and transmit nothing. `MixpanelAnalyticsClient` is the production implementation, shipped as part of F-8.02 (`mixpanel-phase-1-foundation`). Consent is **locale-aware**: default off (explicit opt-in required) in strict-opt-in jurisdictions (EU/EEA/UK/Switzerland and other regimes such as South Korea, China, Brazil, Turkey, Thailand, and Quebec — canonical list in `docs/analytics-spec.md` §7.2), default on (auto opt-in, user can opt out from Settings) in all other locales. No PII is ever transmitted regardless of jurisdiction (no-PII rule operationalized in `docs/analytics-spec.md` §5). The Mixpanel SDK is initialized **lazily**: `Mixpanel.initialize` is NOT called in `init`; the first opted-in `track`/`identify` call triggers lazy initialization guarded by `NSLock`; an opted-out launch incurs zero `MixpanelInstance` creation and no network activity. The "Diagnostics & Analytics" toggle in Settings drives `AppSettings.analyticsOptIn`; toggle-off fires `analytics_consent_changed` then calls `reset()` to wipe the Mixpanel identity. The canonical client-selection table (DEBUG → Console; Release opted-out → Console; Release opted-in → Mixpanel lazy), launch-time event ordering, and consent-transition ordering are in `docs/analytics-spec.md` §§8 and 8.1. The historical implementation starting state (pre-F-8.02 scaffold) is recorded in `docs/analytics-spec.md` §16.1. Fully specified in `docs/analytics-spec.md` §§2–8.
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
| **pre-commit** | **SwiftFormat** (2-space indent, Swift 6, max 200 chars/line; see [`.swiftformat`](../.swiftformat)) — auto-formats staged `*.swift` and re-stages fixes; **SwiftLint `--fix`** — auto-corrects mechanical violations (vertical whitespace, modifier order, sorted imports, etc.) and re-stages; **SwiftLint** strict on staged files ([`.swiftlint.yml`](../.swiftlint.yml)); merge-conflict marker scan; **large-file** guard ([`scripts/check-large-files.sh`](../scripts/check-large-files.sh)) — rejects any staged file over 1 MiB; **gitleaks** on staged changes |
| **pre-push** | **`bash scripts/build.sh`** — bare compile via `xcodebuild build` for scheme `simple-recurring-budgets` using the shared destination helper [`scripts/_destination.sh`](../scripts/_destination.sh) (same resolution as [`scripts/test.sh`](../scripts/test.sh): `SIMULATOR_UDID` → booted sim → `name=iPhone 17,OS=latest` fallback) |

`gitleaks` is optional for solo work but strongly recommended before any secrets or API keys exist in the tree.

The local hooks are bypassable (`--no-verify`, a hookless clone, a web-UI merge); CI (§8.5) re-runs the same gates server-side so they actually run before code reaches `main`.

### 8.3 Manual commands

- `make system` — machine bootstrap: Homebrew packages above, Python 3.9+ and `xcodebuild` checks, `lefthook install` (see [`scripts/system-setup.sh`](../scripts/system-setup.sh))
- `make build` — bare compile via [`scripts/build.sh`](../scripts/build.sh) (same destination resolution as `make test`)
- `make lint` — `swiftlint lint --strict` over the repo
- `make lint-fix` — `swiftlint --fix --quiet .` then `swiftlint lint --strict` (auto-fix + verify)
- `make format` — `swiftformat .` (format everything, not only staged files)
- `make test` — full unit/UI test run via [`scripts/test.sh`](../scripts/test.sh)
- `make hooks-install` — `lefthook install` (refresh hooks after pulling config changes)

### 8.4 Pre-push build caveat

The pre-push build needs a resolvable iOS Simulator (booted device or `SIMULATOR_UDID` / `SIMULATOR_NAME` as in `scripts/test.sh`). If destination resolution fails, run tests once with `make test` or boot a simulator, then push again.

### 8.5 Continuous Integration (GitHub Actions)

CI lives in `.github/workflows/` (checked in, versioned with the code) and re-runs the local gates server-side, where they cannot be bypassed. Branch protection on `main` should **require** the PR checks below (one-time repo-admin toggle in Settings → Branches; CI is advisory without it).

**`ci.yml`** — on every `pull_request` and `push` to `main`:

| Job | Runner | Cost | What |
|-----|--------|------|------|
| `lint` | ubuntu | ~free | SwiftFormat `--lint` + SwiftLint `--strict`, **pinned** to the local Homebrew versions (SwiftLint 0.63.2 / SwiftFormat 0.61.1) to avoid CI-vs-local rule drift. Keep these versions in lockstep with local installs. |
| `secrets` | ubuntu | ~free | `gitleaks detect` (pinned 8.30.1) over full history — complements pre-commit `gitleaks protect --staged`. Reviewed-and-accepted findings are allowlisted by fingerprint in `.gitleaksignore` (currently the historical Mixpanel **project** token — a client-side identifier shipped in the app binary, not a server secret). |
| `i18n-gates` | ubuntu | ~free | `check_translations.py`, `check_source_strings.py`, `check_metadata.py` (the pre-push translation gates), plus a non-blocking `consistency_check.py --ignore-casing`. Enforces issue #172 server-side. |
| `build` | macOS | 10× | `xcodebuild build` (mirrors `scripts/build.sh`). |
| `unit-tests` | macOS | 10× | `xcodebuild test` skipping the UITests target (mirrors `scripts/test-unit.sh`). |

The macOS jobs invoke `xcodebuild` directly (not via the Makefile/sim-sandbox), since the per-repo sim sandbox and `SRB_SIM_MAX` concurrency knob are local optimizations with no analogue on a single ephemeral runner. Xcode is pinned to 26.5. Keep the scheme/`-skip-testing` flags in sync with the mirrored scripts.

**`full-test-on-demand.yml`** — the full UI suite (accessibility + user-journey, 10× and slow) does **not** run per-PR. Comment `/test-full` on a PR (documented in `.github/pull_request_template.md`) to run `scripts/test.sh`'s two-pass flow on demand. Restricted to write-access commenters. `issue_comment` workflows always run the default-branch copy of the file, so changes to this trigger only take effect after merging to `main`.

**`dependabot.yml`** — weekly `github-actions` updates only. The SPM deps (`mixpanel-swift`, `mixpanel-swift-common`, `json-logic-swift`) are **not** Dependabot-trackable because the app has no `Package.swift` (deps are Xcode-project-managed); SPM bumps stay manual.

---

## 9. Future Technical Considerations

Remaining items from the feature backlog that will require technical design when prioritized.

> ⚠️ **Any change that introduces an app extension target** (widget, Live Activity, Lock Screen widget, Control Center widget, App Clip, Share / Action / Intents / Notification Service extension) SHALL first read [§4.7 Multi-process / extension considerations](#47-multi-process--extension-considerations--read-before-shipping-any-extension-target). The store is single-process today; the SwiftData `ModelContainer` migration race across processes is a known production-crash class that must be mitigated in the same change that ships the extension.

| Feature | Technical Surface |
|---------|-------------------|
| **F-4.01–02: Color themes** | Asset Catalog color sets, theme state in `NSUbiquitousKeyValueStore` (synced via iCloud) or SwiftData, `@Environment(\.colorScheme)` integration |
| **F-6.02: Expense Type** | Schema done: `expenseType: String?` on `ExpenseItem`. Remaining: user-facing editor, user-defined values stored as a `Set<String>` in `NSUbiquitousKeyValueStore` (synced via iCloud) or a dedicated entity. |
| ~~**F-6.03: App Store rating prompt**~~ ✓ Implemented (`rating-prompt`) | `RatingPromptCoordinator` + KV-backed `RatingPromptState` (§4.5 `ratingPrompt*` keys); Add-mode expense-save trigger hook; root `ratingPromptPresenter()` calls the native `requestReview`. Cooldown is platform-managed (Apple throttle + once-per-version guard). |
| **F-7.01: Receipt scanning** | Vision framework (`VNRecognizeTextRequest`), on-device OCR, regex extraction for amounts |
| **F-7.02–03: Voice input/query** | SiriKit intents or App Intents framework, on-device NLP, `SFSpeechRecognizer` for in-app voice |
| **F-8.03: Mixpanel Phase 2** | React to Phase 1 evidence; add experimentation seam; extend event coverage per `docs/analytics-spec.md` §§12–15. Operationalized in `docs/analytics-spec.md` §4 / §12–15. |

**Shipped (removed from future table):** F-4.03 budget emoji icons, F-5.01 week start, F-6.01 add funds, F-7.04–07 recents / lifecycle dates / pause-resume, F-8.01–02 OSLog + Mixpanel Phase 1.

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
| 0.23    | 2026-06-02 | Jimmy Ho | Rebrand doc sync: intro and §1 use Wren as product name; §5.1 proper-noun list adds Wren. |
| 0.22    | 2026-06-02 | Jimmy Ho | §4.5 KV-key table: add six `ratingPrompt*` keys (owner `RatingPromptState`, consent-independent) for F-6.03. §9 future table: mark F-6.03 implemented (`rating-prompt`). See `product-features-planning.md` F-6.03 and `analytics-spec.md` §12. |
| 0.21    | 2026-06-01 | Jimmy Ho | §5.3: rewrite testing section — two-pass UI script strategy, `UserJourneyTests` (10 flows, XCTestCase), `AccessibilityAuditTests` runs in pass 2 (not excluded), screen objects, `make test-ui`. Note that Swift Testing is not supported in XCUITest targets. |
| 0.20    | 2026-05-31 | Jimmy Ho | §5.3 add accessibility-audit test note: `AccessibilityAuditTests.swift`, `performAccessibilityAudit()`, excluded from `make test`. |
| 0.19    | 2026-05-31 | Jimmy Ho | Doc/code sync: §4.2 CloudKit container ID set in entitlements; §2.1 documents `AddEditBudgetViewModel` / `AddEditExpenseViewModel`; §3.1 `Budget.icon`; §5.4 `recomputeToken` refresh + `specificDatesBranch` pointer; §7 network surface (Mixpanel + CloudKit, no app backend); §9 future table refreshed (shipped features removed). |
| 0.18    | 2026-05-03 | Jimmy Ho | §4.5 KV-key table: add `analyticsOptIn`, `analyticsDistinctId`, and `analyticsFirstOpenAt` rows (F-8.02). §7 product-analytics paragraph: document lazy Mixpanel SDK init, consent toggle wiring, and PII contract; update §16.1 reference to historical. §9 future table: add F-8.03 Phase 2 row. |
| 0.17    | 2026-05-02 | Jimmy Ho | §7 expanded the on-device diagnostics entry: canonical call-site map for `bootstrap`, `cloudkit`, and `ui` categories; explicit `privacy:` annotation rule; cross-reference to `docs/analytics-spec.md` §17 for the OSLog ↔ `AnalyticsClient` boundary. (F-8.01 implemented by change `oslog-diagnostic-logging`.) |
| 0.16    | 2026-05-02 | Jimmy Ho | §7 expanded the product-analytics paragraph to call out Mixpanel SDK lazy init, the canonical client-selection table, and cross-references to `docs/analytics-spec.md` §§8 / 8.1 (ordering) and §16.1 (implementation starting state) ahead of F-8.01 / F-8.02 OpenSpec planning. |
| 0.15    | 2026-04-30 | Jimmy Ho | §5.1 add `Text(verbatim:)` rule for locale-invariant strings (app version + build, raw ISO codes, etc.) so they are not auto-extracted into the catalog as opaque `%@`-format keys; pair with a localized `accessibilityLabel` when the row exposes translatable copy via VoiceOver. |
| 0.14    | 2026-04-30 | Jimmy Ho | Loc + VoiceOver audit conventions: §5.1 add shared-key (`common.*`) policy; §5.2 codify single-element composite a11y, header rotor trait, destructive hint requirement, and `swipeActions` ↔ `accessibilityAction` pairing rule. Cross-link audit at `docs/audits/localization+voiceover-audit-2026-04-30.md`. |
| 0.13    | 2026-04-30 | Jimmy Ho | Continued drift audit (phase 2): §3.2 fix broken anchor link (67-overunder → 67-carry-over); §5.5 document color-literal exceptions (money, sync status, destructive tints); §9 mark F-5.01 as shipped, update F-6.01/F-6.02 partial-impl notes |
| 0.12    | 2026-04-30 | Jimmy Ho | Doc/code drift audit: §2.2 fix Router ownership (app entry point, not RootView); §8.2 fix pre-push to reference `scripts/build.sh` + `_destination.sh`; §8.3 add `make build`, `make lint-fix`, `make hooks-install` |
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
