<!--
  This delta removes the entire `first-run-seed` capability before it ever lands in
  `openspec/specs/`. The capability was defined only inside the pending change
  `openspec/changes/add-first-run-seeder/` (35/35 tasks complete, never archived).
  This change supersedes that pending change by deleting its directory; there is no
  corresponding capability in main specs today, and none will exist after this change
  archives. The REMOVED blocks below mirror the requirement names from the superseded
  delta so reviewers can trace the reversal one-to-one.
-->

## REMOVED Requirements

### Requirement: FirstRunSeeder service

**Reason**: The `FirstRunSeeder` namespace (and its `seedIfNeeded(context:store:isCarryOverEnabled:now:)` entry point) was introduced to insert a placeholder `"Food"` Budget on first launch. We are backing out that UX: see `proposal.md` → Why and `design.md` → Decision 1.

**Migration**: None. Delete `App/FirstRunSeeder.swift`. Remove its invocation from `simple_recurring_budgetsApp.swift`'s `.task` (see the "Integration via ContentView .task" removal below). Existing installs that ran an earlier build keep their seeded `"Food"` Budget as a user-owned record; no app-side cleanup is required.

### Requirement: SeedResult return type

**Reason**: `SeedResult` exists only as the return type of `FirstRunSeeder.seedIfNeeded`; removing the seeder removes the only caller and producer.

**Migration**: None. Delete the enum with the surrounding file.

### Requirement: Two-gate seed decision

**Reason**: The two-gate decision (KV flag `"seededV1"` + `FetchDescriptor<Budget>` count) exists solely to guard the seed insert. With no seed, there is no decision to make on launch.

**Migration**: None. No replacement gating logic runs at launch.

### Requirement: Seed Budget field values

**Reason**: The canonical seed payload (`name: "Food"`, `allocation: 25`, `period: .daily`, `resetCadence: .weekly`, locale-default `currencyCode`, `isCarryOverEnabled` from `AppSettings`) is no longer produced by the app.

**Migration**: None. Users create budgets themselves from the Add/Edit Budget screen (F-2.03) once F-2.01 ships.

### Requirement: Seed, save, flag write ordering

**Reason**: The strict insert → `context.save()` → flag-write ordering is only meaningful while the seed exists. No save is performed at launch.

**Migration**: None.

### Requirement: Store-non-empty flag sealing

**Reason**: Forward-sealing `"seededV1" = true` when the store is non-empty prevented a later delete-all from reseeding. With seeding removed, there is nothing to seal against.

**Migration**: None. Existing installs that already wrote `"seededV1" = true` keep the value in `NSUbiquitousKeyValueStore`; the app no longer reads it. See `design.md` → Decision 3.

### Requirement: KV key constant

**Reason**: `FirstRunSeeder.firstRunSeededV1Key` ("seededV1") is declared only to be read/written by the seeder. No other code reads or writes this key.

**Migration**: Do NOT reuse the string `"seededV1"` for any future iCloud KV key. The `V1` suffix remains reserved (per the original tech-design rule) so any hypothetical future one-time-reseed change introduces a distinct key (e.g., `"seededV2"`). Document the orphaned-but-reserved status in `docs/tech-design-doc.md` §4.5.

### Requirement: Idempotency across repeated calls

**Reason**: Repeated-call idempotency is a property of `FirstRunSeeder.seedIfNeeded`; removing the seeder removes the need for the property.

**Migration**: None.

### Requirement: Integration via ContentView .task

**Reason**: The `.task` modifier that invoked `FirstRunSeeder.seedIfNeeded` is being collapsed to a single-line `analytics.track(AnalyticsEvent.appLaunched)` per `design.md` → Decision 5. The `ContentView` Budgets root no longer performs any seeding-related work.

**Migration**: None at the view layer. The `appLaunched` analytics event continues to fire exactly once per launch from the same `.task` scope; the seeder-specific `firstRun.seeded` / `firstRun.skipped` / `firstRun.error` events are removed.

### Requirement: Testability seam via KeyValueStore and in-memory ModelContainer

**Reason**: The testability seam exists specifically for `FirstRunSeederTests`. The seeder and its test file are both deleted; `MockKeyValueStore` and the in-memory `ModelContainer` helper remain available for other tests (e.g., `AppSettings`, lifecycle services) and are unaffected.

**Migration**: None. No existing non-seeder test depends on any seeder-specific helper.
