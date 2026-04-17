## ADDED Requirements

### Requirement: FirstRunSeeder service

The system SHALL define a caseless `enum FirstRunSeeder` in `App/FirstRunSeeder.swift` that exposes a single entry point for the first-run seed decision:

```swift
@discardableResult
static func seedIfNeeded(
    context: ModelContext,
    store: KeyValueStore,
    isCarryOverEnabled: Bool,
    now: Date = Date()
) async throws -> SeedResult
```

All time-dependent inputs (`now`) and external collaborators (`context`, `store`) SHALL be parameters so that tests can inject deterministic values and the in-memory `ModelContainer` / `MockKeyValueStore` helpers. The service SHALL NOT read from `NSUbiquitousKeyValueStore.default`, `AppSettings`, or any global state directly.

#### Scenario: Entry point signature and defaults

- **WHEN** a caller invokes `FirstRunSeeder.seedIfNeeded(context:store:isCarryOverEnabled:)` without a `now` argument
- **THEN** the call SHALL compile and `now` SHALL default to `Date()`

#### Scenario: Dependencies are injected

- **WHEN** the service is invoked with a `MockKeyValueStore` and an in-memory `ModelContext`
- **THEN** the service SHALL read and write only through those injected dependencies and SHALL NOT access `NSUbiquitousKeyValueStore.default` or any other global store

---

### Requirement: SeedResult return type

The system SHALL define a `SeedResult` enum with exactly these cases, returned by `seedIfNeeded` to signal which branch was taken:

- `.seeded` — Both gates were open; the service inserted the seed Budget, saved the context, and wrote the flag.
- `.skippedFlagAlreadySet` — Gate A was closed (the KV flag was already `true`); the service did not read the store count and did not mutate anything.
- `.skippedStoreNonEmpty` — Gate A was open but Gate B was closed; the service did not insert a Budget; see the "store-non-empty flag sealing" requirement for what it writes.
- `.skippedStoreNonEmptyFlagSealed` — Gate A was open, Gate B was closed, and the service wrote `"seededV1" = true` to forward-seal against future reseeds.

`.skippedStoreNonEmpty` and `.skippedStoreNonEmptyFlagSealed` SHALL be distinct cases so that tests can assert the flag-sealing branch explicitly; production code that collapses "any store-non-empty skip" can pattern-match both.

#### Scenario: Seeded return value

- **WHEN** both gates are open on entry and the seed/save/flag sequence succeeds
- **THEN** `seedIfNeeded` SHALL return `.seeded`

#### Scenario: Flag-already-set return value

- **WHEN** the store already has `"seededV1"` set to any non-nil value on entry
- **THEN** `seedIfNeeded` SHALL return `.skippedFlagAlreadySet` without reading `Budget` count

#### Scenario: Store-non-empty flag-sealed return value

- **WHEN** `"seededV1"` is unset on entry but the store contains at least one `Budget`, and the flag write succeeds
- **THEN** `seedIfNeeded` SHALL return `.skippedStoreNonEmptyFlagSealed`

---

### Requirement: Two-gate seed decision

The service SHALL seed the store only when BOTH of the following are true on entry:

- **Gate A (KV flag):** `store.object(forKey: FirstRunSeeder.firstRunSeededV1Key) == nil`
- **Gate B (store count):** `try context.fetchCount(FetchDescriptor<Budget>()) == 0`

When Gate A is closed, the service SHALL return `.skippedFlagAlreadySet` immediately and SHALL NOT read the `Budget` count. When Gate A is open and Gate B is closed, the service SHALL NOT insert a `Budget`; see the "store-non-empty flag sealing" requirement for the flag behavior in that branch.

#### Scenario: Gate A closed short-circuits before store read

- **WHEN** `store.object(forKey: "seededV1")` returns a non-nil value on entry
- **THEN** the service SHALL NOT call `context.fetchCount(FetchDescriptor<Budget>())` and SHALL return `.skippedFlagAlreadySet`

#### Scenario: Both gates open trigger seed

- **WHEN** `store.object(forKey: "seededV1")` is `nil` and `context.fetchCount(FetchDescriptor<Budget>())` returns `0` on entry
- **THEN** the service SHALL proceed with the seed insert

#### Scenario: Gate A open, Gate B closed does not seed

- **WHEN** `store.object(forKey: "seededV1")` is `nil` and the store already contains one or more `Budget` records
- **THEN** the service SHALL NOT insert a new `Budget` and SHALL NOT call `context.save()` for a seed

---

### Requirement: Seed Budget field values

When the service seeds, it SHALL insert exactly one `Budget` constructed as:

- `name: "Food"`
- `allocation: Decimal(25)`
- `period: BudgetPeriod.daily`
- `resetCadence: ResetCadence.weekly` (passed explicitly, not inherited from `BudgetPeriod.daily.defaultResetCadence`)
- `isCarryOverEnabled:` the value of the `isCarryOverEnabled` parameter passed to `seedIfNeeded`
- `currencyCode:` the default produced by `Budget.init` (locale currency identifier, falling back to `"USD"`) — not passed explicitly by the seeder

After `Budget.init`, the service SHALL set `budget.sortOrder = try Budget.nextSortOrder(for: context)` before calling `context.insert(budget)`.

#### Scenario: Seed field values match F-2.06

- **WHEN** the seed insert is executed
- **THEN** the inserted `Budget` SHALL have `name == "Food"`, `allocation == 25`, `period == BudgetPeriod.daily.rawValue`, `resetCadence == ResetCadence.weekly.rawValue`, `isCarryOverEnabled == <injected>`, and `currencyCode` equal to `Locale.current.currency?.identifier ?? "USD"`

#### Scenario: isCarryOverEnabled sourced from caller

- **WHEN** the seeder is called with `isCarryOverEnabled: false`
- **THEN** the inserted `Budget.isCarryOverEnabled` SHALL be `false`

#### Scenario: sortOrder uses canonical helper

- **WHEN** the seed is inserted into an empty store
- **THEN** the inserted `Budget.sortOrder` SHALL equal the value returned by `Budget.nextSortOrder(for: context)` at the moment of insertion (trivially `0` on an empty store)

---

### Requirement: Seed, save, flag write ordering

The service SHALL execute these steps in this strict order when both gates are open:

1. Construct and `context.insert(budget)` the seed Budget.
2. Call `try context.save()`.
3. Only after `save()` returns without throwing, call `store.set(true, forKey: FirstRunSeeder.firstRunSeededV1Key)` followed by `_ = store.synchronize()`.

The flag SHALL NOT be written before `context.save()` returns successfully. If `context.save()` throws, the service SHALL rethrow, the flag SHALL remain unset, and the next launch SHALL be able to retry the full seed.

#### Scenario: Successful seed writes flag after save

- **WHEN** both gates are open and `context.save()` succeeds
- **THEN** the service SHALL call `store.set(true, forKey: "seededV1")` and `store.synchronize()` after the save, and SHALL return `.seeded`

#### Scenario: Save failure leaves flag unset

- **WHEN** both gates are open and `context.save()` throws
- **THEN** the service SHALL rethrow the error and SHALL NOT write `"seededV1"` to the store

---

### Requirement: Store-non-empty flag sealing

When Gate A is open (flag unset) and Gate B is closed (store already contains at least one `Budget`), the service SHALL write `store.set(true, forKey: FirstRunSeeder.firstRunSeededV1Key)` and call `store.synchronize()` before returning, to forward-seal the decision against future reseeds. This branch SHALL NOT call `context.save()` and SHALL NOT insert any model.

#### Scenario: Flag forward-sealed when store has budgets

- **WHEN** `"seededV1"` is unset and the store contains at least one `Budget`
- **THEN** the service SHALL write `"seededV1" = true` to the store, call `synchronize()`, and return `.skippedStoreNonEmptyFlagSealed`

#### Scenario: Subsequent launches do not reseed after forward-seal

- **WHEN** the forward-seal branch has written `"seededV1" = true`, the user later deletes every `Budget` from the store, and the service is called again
- **THEN** the service SHALL return `.skippedFlagAlreadySet` and SHALL NOT insert a new seed `Budget`

---

### Requirement: KV key constant

The system SHALL declare the key used for the first-run flag as a public constant: `FirstRunSeeder.firstRunSeededV1Key: String = "seededV1"`. No other code in the app SHALL read or write this key.

The `V1` suffix SHALL be preserved verbatim; future changes that want to force a one-time re-seed SHALL introduce a distinct key (e.g., `"seededV2"`) rather than reusing or mutating `"seededV1"`.

#### Scenario: Key constant value

- **WHEN** `FirstRunSeeder.firstRunSeededV1Key` is inspected
- **THEN** it SHALL equal the string `"seededV1"`

---

### Requirement: Idempotency across repeated calls

The service SHALL be safe to call any number of times per app session. On any call after a prior `.seeded` or `.skippedStoreNonEmptyFlagSealed` result, the service SHALL short-circuit at Gate A and return `.skippedFlagAlreadySet` without mutating the store or the context.

#### Scenario: Second call returns flag-already-set

- **WHEN** `seedIfNeeded` has previously returned `.seeded` on the same `KeyValueStore`
- **AND** `seedIfNeeded` is called again with the same `store`
- **THEN** the second call SHALL return `.skippedFlagAlreadySet` and SHALL NOT insert a new `Budget`

#### Scenario: Multiple windows do not duplicate seeds

- **WHEN** two `.task` invocations call `seedIfNeeded` in close succession on the same `ModelContext` and `KeyValueStore` with Gate A and Gate B both open
- **THEN** at most one seed `Budget` SHALL be inserted and the final store SHALL contain exactly one `Budget` with `name == "Food"` from this path

---

### Requirement: Integration via ContentView .task

The Budgets root (currently the placeholder content at the root of `ContentView`'s `NavigationStack`) SHALL attach a `.task` modifier that invokes `FirstRunSeeder.seedIfNeeded` using:

- `context:` the `@Environment(\.modelContext)` value
- `store:` `NSUbiquitousKeyValueStore.default`
- `isCarryOverEnabled:` the current value of `@Environment(AppSettings.self).defaultCarryOverEnabled`

Errors from `seedIfNeeded` SHALL be swallowed at the call site with `try?`. The `.task` SHALL NOT block rendering; it SHALL NOT display user-facing error UI.

Until the real Budgets screen exists (future change, F-2.01), this wiring may live on the placeholder root content; it SHALL move to the Budgets list root when that screen is introduced. The wiring location is on the Budgets root specifically, not the sheet layer or a navigation destination.

#### Scenario: ContentView calls seeder on appearance

- **WHEN** `ContentView` becomes visible
- **THEN** it SHALL invoke `FirstRunSeeder.seedIfNeeded` exactly once per view-identity lifetime via a `.task` modifier on its Budgets root

#### Scenario: Seeder errors are silently ignored by the view

- **WHEN** `FirstRunSeeder.seedIfNeeded` throws
- **THEN** `ContentView` SHALL NOT present an alert, log a user-visible message, or otherwise surface the error

---

### Requirement: Testability seam via KeyValueStore and in-memory ModelContainer

The service SHALL be fully unit-testable without touching `NSUbiquitousKeyValueStore.default` or a real CloudKit-backed container. Tests SHALL drive the service using:

- `MockKeyValueStore` (already defined in `Settings/KeyValueStore.swift`) for the `store` parameter.
- An in-memory `ModelContainer` (via the project's existing `simple-recurring-budgetsTests/Helpers/` helper) for the `context` parameter.
- Injected `now: Date` for determinism when asserting `createdAt` or `lastModified` is not required for seeder correctness but SHALL be supported.

#### Scenario: Tests run without iCloud

- **WHEN** `FirstRunSeederTests` is executed
- **THEN** it SHALL NOT read or write `NSUbiquitousKeyValueStore.default` and SHALL NOT require network or CloudKit access

#### Scenario: MockKeyValueStore satisfies the protocol

- **WHEN** `MockKeyValueStore` is passed to `seedIfNeeded`
- **THEN** all reads and writes SHALL be routed through the mock, and its internal storage SHALL reflect the service's writes in-order
