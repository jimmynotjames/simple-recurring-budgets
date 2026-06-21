# Architecture

A high-level, human-readable map of how **Wren** is built — the kind of overview you'd want before reading the code.

> This is the friendly version of [`docs/tech-design-doc.md`](docs/tech-design-doc.md), which is the exhaustive technical reference. (That doc was originally drafted by hand and then extended heavily by AI over the life of the project.) When the two disagree, the tech-design doc and the code win.

## The one-paragraph version

Wren is a native SwiftUI app for iPhone and iPad. There is **no backend** — every byte of user data lives on-device in SwiftData and syncs across the user's own devices through CloudKit. SwiftUI screens read data reactively and hand all the non-trivial budget math to a layer of pure, well-tested Swift services. Money is always `Decimal`, currency is per-budget, and the app targets only the latest iOS so there's little legacy surface to maintain.

## Guiding principles

- **No server.** CloudKit (the user's iCloud) is the only "backend." Nothing to operate, nothing to pay for, nothing to breach.
- **Apple-first, few dependencies.** One direct third-party package (Mixpanel). Everything else is Apple frameworks. Fewer moving parts age better.
- **Latest OS only.** Minimal backward-compatibility code; built to need little maintenance for years.
- **Logic out of the UI.** Budget math lives in pure services with no SwiftUI or SwiftData dependencies, so it's trivially testable.
- **Money is `Decimal`.** Never floating point, anywhere.

## The layers

```
┌─────────────────────────────────────────────┐
│  Views (SwiftUI)                             │  Budgets list, Budget detail,
│  - read data with @Query                     │  Add/Edit Budget, Add/Edit Expense,
│  - navigate via a small Router               │  Settings
├─────────────────────────────────────────────┤
│  ViewModels (only where earned)              │  Add/Edit forms with draft state
├─────────────────────────────────────────────┤
│  Domain services (pure Swift, no UI/no DB)   │  PeriodCalculator, BudgetCalculator,
│  - all the budget & carry-over math          │  BudgetLifecycleService
├─────────────────────────────────────────────┤
│  Models (SwiftData @Model)                   │  Budget, ExpenseItem,
│                                              │  AllocationChange, LifecycleEvent
├─────────────────────────────────────────────┤
│  Persistence + Sync                          │  SwiftData on-disk store
│                                              │  ⇄ CloudKit  +  iCloud key-value (settings)
└─────────────────────────────────────────────┘
```

### Views — and ViewModels only when earned

Screens are plain SwiftUI views. They read with `@Query` (so SwiftUI auto-refreshes when data changes) and write through the model context. They **don't** get a companion ViewModel by default — most screens are thin, and the real logic already lives in the domain layer. A view only graduates to an `@Observable` ViewModel when it has genuine draft/form state to manage (the Add/Edit Budget and Add/Edit Expense sheets). This keeps the bulk of the app boilerplate-free.

### Navigation

A single `NavigationStack` with a tiny `Router`. Routes carry a model's stable `UUID`, never a live object — so navigation state stays serializable (good for future deep links, widgets, and App Intents) and gracefully no-ops if the target was deleted on another device.

### The domain layer (the interesting part)

All budget math is pure functions over plain values — no database, no UI:

- **`PeriodCalculator`** — date math: where does each daily/weekly/biweekly/monthly period start and end.
- **`BudgetCalculator`** — the heart of the app. Given a budget and its expenses, it computes "how much is left this period" and the running **carry-over**.
- **`BudgetLifecycleService`** — the entry point screens actually call; also handles the writes (reset, pause/resume, allocation edits).

The carry-over number is the one genuinely tricky idea, and it's **never stored** — it's recomputed on the fly from history every time, by a "live walker" that sums each past period's surplus/deficit. The rule with personality: an overspend hits your carry-over *immediately* (bad news lands live), but being under budget mid-period doesn't count until the period actually closes (you might still spend it). Full algorithm: [`docs/budget-calculations-rewrite-algorithm.md`](docs/budget-calculations-rewrite-algorithm.md).

### Data model

Four SwiftData entities, all owned by `Budget`:

- **`Budget`** — name, currency, period, dates, carry-over toggle, icon.
- **`ExpenseItem`** — a signed `Decimal` amount (negative = "add funds"), date, optional note.
- **`AllocationChange`** — history of allocation amounts, so editing "$20/day → $25/day" doesn't rewrite the past.
- **`LifecycleEvent`** — pause/resume history.

Deleting a budget cascade-deletes all of its children. Derived numbers (remaining, carry-over) are computed, never columns.

### Persistence & sync

SwiftData is the local store; CloudKit mirroring is switched on with one configuration flag. Two details worth knowing:

- **No split-brain.** The app tries a CloudKit-backed store first and falls back to local-only when iCloud is unavailable — but both are pinned to the *same* on-disk file. So an offline first launch isn't stranded in a separate empty store; when iCloud returns, that same data is promoted to the cloud.
- **Settings sync separately.** Lightweight preferences (week-start day, currency display, analytics opt-in, etc.) live in `NSUbiquitousKeyValueStore`, which syncs through the same iCloud account without involving SwiftData.

If the store genuinely can't be created (disk full, corruption), the app shows a Retry / Send-Feedback screen instead of crashing.

## Cross-cutting concerns (always-on, not features)

These are treated as standing requirements for every change, and several are enforced in CI:

- **Localization** — 49 App Store locales, via a custom AI translation pipeline (`scripts/translate_catalog/`).
- **Accessibility** — Dynamic Type, VoiceOver, and Dark Mode are per-change obligations, verified by automated accessibility-audit UI tests.
- **Privacy-first analytics** — Mixpanel, lazy-initialized and consent-gated, no PII; on-device diagnostics use Apple's `OSLog`.

## Testing

- **Unit tests** (Swift Testing) cover the domain layer in isolation with in-memory stores — fast and deterministic.
- **UI tests** (XCUITest) drive real user journeys plus a suite of accessibility audits, organized behind reusable screen objects.

## What's deliberately *not* here

No app-owned server. No widgets / extensions yet (the store assumes a single process — a known thing to revisit before adding one). No schema-migration machinery yet (still greenfield on `SchemaV1`). No third-party UI frameworks.

---

*For the full detail behind any of the above — exact types, field tables, CloudKit constraints, the tooling/CI matrix — see [`docs/tech-design-doc.md`](docs/tech-design-doc.md).*
