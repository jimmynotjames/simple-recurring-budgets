# Technical Design Document

| Field              | Value                          |
| ------------------ | ------------------------------ |
| **Version**        | 0.1                            |
| **Last Updated**   | 2026-04-10                     |
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

---

## 5. Internationalization, Accessibility, and Testing

### 5.1 Internationalization

All user-facing text uses Xcode **String Catalogs** and `LocalizedStringKey` — no hard-coded English in production views. Dates and numbers use Foundation format styles that auto-adapt to locale. Each Budget stores its own ISO 4217 currency code; formatting uses `Decimal.FormatStyle.Currency`.

### 5.2 Accessibility

- **Dynamic Type**: System text styles everywhere; no fixed frame heights that clip at larger sizes.
- **VoiceOver**: Meaningful accessibility labels on all interactive controls; financial amounts include currency context.
- **Dark Mode**: Semantic system colors and Asset Catalog color sets with light/dark variants; no hard-coded color literals.

### 5.3 Testing

**Swift Testing** for all new tests; XCTest for UI tests where needed. In-memory `ModelContainer` for all automated data tests to ensure isolation. Business logic (budget math, Over/Under rolls, date boundaries) lives in pure, testable services with no SwiftData/UI dependencies.

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
