## Context

The app's entry point (`simple_recurring_budgetsApp`) currently wires the `ModelContainer` (CloudKit-first with a local-only fallback) and injects `AppSettings` into the environment. `ContentView` hosts a `NavigationStack` with placeholder text at the Budgets root. `AppSettings` already owns iCloud-synced preferences through a `KeyValueStore` protocol abstraction (`NSUbiquitousKeyValueStore` in production, `MockKeyValueStore` in tests). `Budget.init` defaults `currencyCode` from `Locale.current.currency?.identifier ?? "USD"`, `isCarryOverEnabled: true`, and resolves `resetCadence` from `BudgetPeriod.defaultResetCadence` when not specified. `Budget.nextSortOrder(for:)` returns the next sort slot, and trivially returns `0` when the store is empty.

F-2.06 requires that on first launch with an empty store, the app seeds one Budget so the user does not land on an empty screen. The seed must run exactly once per iCloud account across all the user's devices and installs — reinstalling on a device that previously had the app, or installing on a second synced device, must not trigger a second seed — and the user intentionally deleting all their budgets later must not cause a reseed.

Two environmental realities complicate "run once":

1. **`NSUbiquitousKeyValueStore` has eventual consistency.** A fresh install on a synced device will typically see the iCloud KV store populated within seconds to minutes, but not necessarily before the app first draws. If the KV flag is the only gate and it hasn't synced yet, a fresh-install-with-prior-data device will reseed.
2. **SwiftData+CloudKit also has eventual consistency.** Conversely, the SwiftData store may already contain budgets (synced from CloudKit) before the KV flag arrives — or a power-user edge case: the local store is non-empty on first launch because CloudKit replicated faster than KV did.

Neither gate is individually sufficient. The store-count check handles case (2); the KV flag handles case (1) and the far more common "user deleted all budgets months ago" case, where the store is empty but we must not reseed.

Nothing in the codebase currently performs this bootstrap; this change adds exactly one narrow service and one `.task` wiring.

## Goals / Non-Goals

**Goals:**

- Implement F-2.06 acceptance criteria end-to-end: the seeded Budget appears on the Budgets root after first launch with an empty store, matches the specified field values, and the seed runs at most once per iCloud account.
- Keep the seeder a pure namespace service with injected dependencies (`ModelContext`, `KeyValueStore`, `isCarryOverEnabled`, `now`) so it is fully unit-testable without SwiftUI or a real iCloud store.
- Use the existing `KeyValueStore` protocol and `MockKeyValueStore` seam rather than introducing a new testability layer.
- Make the decision logic self-explanatory: two explicit gates, documented in code, each with an obvious failure mode if you think about removing it.
- Match the Add/Edit Budget screen's field resolution (F-2.03) so a seeded Budget is indistinguishable from a user-created one in every observable way (other than name/amount/period/cadence, which F-2.06 pins).
- Preserve the "flag write only after successful save" ordering so a crash window produces at worst one duplicate, never zero seeds forever.

**Non-Goals:**

- No Budgets screen, Budget detail screen, or Add/Edit Budget screen are built or wired here. `ContentView` retains its placeholder root; only a `.task` modifier is added.
- No changes to `AppSettings` public API. The seeder reads `defaultCarryOverEnabled` through `AppSettings` but does not mutate settings.
- No new persisted fields on `Budget`, `ExpenseItem`, `SchemaV1`, or the migration plan.
- No background seeding, no retry queue, no telemetry. `try?` + "the next launch retries if both gates are still open" is the recovery story.
- No migration of existing installs (the app has no released installs yet; first shipping version is the first launch for every user).
- No UI-level empty state. F-2.06 satisfies "not empty" by seeding; a later change may add an empty-state design for the post-delete case, but that is out of scope here.
- No versioning of the seed key beyond `"seededV1"`. If a future change wants to re-seed everyone (e.g., `"seededV2"`), that is a separate change; this design does not anticipate a generic "schema of seeds" mechanism.

## Decisions

### 1. Two-gate decision: iCloud KV flag AND empty store

**Decision:** Seed only when BOTH are true:

- `store.object(forKey: "seededV1") == nil`
- `try context.fetchCount(FetchDescriptor<Budget>()) == 0`

After a successful seed, write the flag (`store.set(true, forKey: "seededV1")` + `synchronize()`). After a no-seed-but-store-non-empty path (flag unset, store has data — i.e., a reinstall where CloudKit synced faster than KV), **also write the flag**, to forward-seal the decision so the user cannot accidentally "reseed" by later emptying their store before KV syncs again.

**Why over a single-gate approach:**

- *KV-flag only:* Misses the reinstall-on-synced-device case when KV is slow. The user would see their existing synced budgets *plus* a duplicate "Food" seed. The duplicate is harmless and deletable, but it violates F-2.06's "seed runs once" acceptance criterion.
- *Store-count only:* Misses the "user deleted all budgets months after first install" case. F-2.06 explicitly says "deleting all budgets later does not auto-reseed" — the flag is the only thing that remembers we've been here before.
- *Both:* Each gate closes what the other misses. The combination is boring, obvious, and costs one extra `fetchCount` on cold launch — negligible on an empty or near-empty store.

**Alternative considered:** A timed "wait for KV sync before checking the flag" approach (e.g., delay 2 seconds on first launch). Rejected: fragile (no guaranteed sync window exists; CloudKit traffic is opaque), user-hostile (gratuitous delay on every first launch), and more complex than the two-gate approach.

### 2. Flag write ordering: after `context.save()`, not before

**Decision:** The sequence is `insert → save → write flag → synchronize`. The flag is written only if `save()` succeeds (no throw).

**Why:** If the flag were written first and the save then failed (disk full, CloudKit rejection, SwiftData error), the flag would permanently suppress future seeding; the user would see an empty app forever, with no path to recovery short of reinstalling and clearing iCloud. Writing the flag after save means the worst case is a crash or error between `save()` and the flag write — in that case, the next launch sees Gate A open (flag still unset) and Gate B closed (a Budget exists from the partial success), so we take the "store non-empty" branch, don't re-seed, and forward-seal the flag. If the `save()` itself threw, both gates remain open and the next launch retries cleanly.

**Alternative considered:** Writing the flag first, inside a transaction that can be rolled back. SwiftData does not expose atomic transactions across a `@Model` write and a `KeyValueStore` write — they live in different subsystems. An all-or-nothing semantic is impossible; the best we can do is order for the recoverable failure mode.

### 3. Entry point shape: async, injected dependencies

**Decision:** The entry point is:

```swift
@discardableResult
static func seedIfNeeded(
    context: ModelContext,
    store: KeyValueStore,
    isCarryOverEnabled: Bool,
    now: Date = Date()
) async throws -> SeedResult
```

- `async throws` so the caller (`.task { try? await ... }`) can await without blocking SwiftUI's render, and so future enhancements (e.g., waiting briefly for CloudKit if we ever want to) can slot in without a signature break. The initial implementation does not `await` anything meaningful; the `async` is future-proofing at effectively zero cost.
- `KeyValueStore` (protocol) rather than `NSUbiquitousKeyValueStore` directly — preserves testability with `MockKeyValueStore`.
- `isCarryOverEnabled: Bool` rather than `AppSettings` as a whole — the seeder only needs this one value, and passing the primitive avoids pulling `AppSettings` (a `@MainActor`-adjacent `@Observable`) into test setup. The `ContentView.task` reads `settings.defaultCarryOverEnabled` and passes the `Bool` through.
- `now: Date = Date()` mirrors the `BudgetLifecycleService` convention and lets tests pin time if they need to assert `createdAt` / `lastModified` values.

**`SeedResult` return type:** A lightweight enum with cases `.seeded`, `.skippedFlagAlreadySet`, `.skippedStoreNonEmpty`, `.skippedStoreNonEmptyFlagSealed`. Returning a result type (vs. `Void`) is marginally more useful for tests and future telemetry without being speculative — each case is a real branch the tests already need to distinguish.

**Alternative considered:** Static sync function taking `AppSettings` and returning `Void`. Rejected for the testability and future-proofing reasons above.

### 4. File location: `App/`, not `Domain/` or a new `Bootstrap/`

**Decision:** `simple-recurring-budgets/App/FirstRunSeeder.swift`, alongside `simple_recurring_budgetsApp.swift`, `AppRoute.swift`, and `SheetRoute.swift`.

**Why:** `Domain/` currently houses pure math and lifecycle orchestration for already-existing data. First-run seeding is an app-lifecycle bootstrap concern — closer in spirit to "what the app does on launch" than to "how a Budget's numbers are computed." Keeping it in `App/` groups it with the other launch-time scaffolding and avoids implying that `Domain/` owns write paths other than the lifecycle service. Creating a new `Bootstrap/` group for a single file is overkill.

**Alternative considered:** `Domain/FirstRunSeeder.swift`. Rejected because it blurs the intent of `Domain/` (pure math + lifecycle) with lifecycle-of-the-app concerns.

### 5. Integration point: `.task` on `ContentView`, not on `WindowGroup`

**Decision:** Attach a `.task` modifier at the Budgets root inside `ContentView` that reads `@Environment(\.modelContext)` and `@Environment(AppSettings.self)` and calls the seeder.

**Why:**

- `.task` is async-native, structured-concurrency-aware, and automatically cancelled when the view disappears — the right primitive for launch-time work that touches actor-bound state (`ModelContext`).
- `ContentView` is where the `ModelContext` environment value is in scope (the `modelContainer` modifier is on `WindowGroup` in `simple_recurring_budgetsApp`, which makes the context available to its contents — `ContentView`). Moving the seeder to `WindowGroup.onAppear` would require manually threading the `ModelContainer` into the closure, which is less clean.
- Multiple windows on macOS/iPadOS will each get a `.task` fire, but the seeder's two-gate check is idempotent: second, third, and nth calls all hit `.skippedFlagAlreadySet` immediately after the first succeeds. No extra guard needed.

**Alternative considered:** A dedicated `@MainActor` `AppBootstrapper` object attached to the `App` value with `@State` and kicked off in `WindowGroup.onAppear`. Rejected as heavier than needed; the seeder has no state to retain and benefits from being a namespace function.

### 6. Seed field values: explicit in call, not relying on Budget init defaults

**Decision:** The seeder constructs the Budget with every F-2.06-specified field passed explicitly to `Budget.init`:

```swift
let budget = Budget(
    name: "Food",
    allocation: 25,
    // currencyCode omitted → uses Budget.init default (locale → USD)
    period: .daily,
    resetCadence: .weekly,
    isCarryOverEnabled: isCarryOverEnabled
)
budget.sortOrder = try Budget.nextSortOrder(for: context)
context.insert(budget)
```

- `name`, `allocation`, `period`, `resetCadence`, `isCarryOverEnabled` are passed explicitly — F-2.06 pins each, and explicit call sites are more readable and more test-assertable than "inherits from default."
- `currencyCode` is *not* passed; `Budget.init`'s default (`Locale.current.currency?.identifier ?? "USD"`) matches F-2.06 / F-2.03 by construction. Passing `Locale.current.currency?.identifier ?? "USD"` at the call site would duplicate logic with no benefit.
- `resetCadence: .weekly` is passed explicitly even though it equals `BudgetPeriod.daily.defaultResetCadence`, because F-2.06's wording ("weekly (per main-prd §6.7)") is a contract, not an incidental equality — if the default for daily ever changes, the seed should stay weekly until F-2.06 changes.
- `sortOrder` uses `Budget.nextSortOrder(for:)`. Trivially `0` on an empty store, but calling the canonical method keeps the seeder compatible with any future behavior change (e.g., a non-zero "starter slot").

**Alternative considered:** Hardcode `sortOrder = 0`. Rejected for the consistency reason above.

### 7. Error handling: `try?` at the call site, `throws` at the service

**Decision:** `FirstRunSeeder.seedIfNeeded` throws for `fetchCount` and `context.save()` errors (re-thrown from SwiftData). The `ContentView.task` wraps the call in `try?` and ignores the result: if seeding fails, the Budgets root stays empty and the user can create a budget manually.

**Why:**

- Throwing in the service preserves information for tests (they can assert "the correct error propagated"). Swallowing in the view matches the app's existing fire-and-forget posture for eager writes (`BudgetLifecycleService` uses `try? context.save()` similarly).
- No user-facing error UI is justified for this path: the only recoverable action is "create a budget yourself," which the UI will already offer. An error alert on first launch would be worse UX than the empty state.

### 8. Key name: `"seededV1"`, documented as the single seed-version key

**Decision:** The KV key is exactly `"seededV1"`, declared as a `static let firstRunSeededV1Key = "seededV1"` on `FirstRunSeeder`. The `V1` suffix is intentional: if a future change requires *re-seeding* every user (e.g., to backfill a new mandatory budget for a new feature), that change can introduce a separate `"seededV2"` key with its own gate logic, without colliding with `"seededV1"` or requiring a migration of existing users' KV state.

**Why not `"firstRunSeeded"` without a version:** Versioning is free here and cheap to read. Zero-versioning a key usually leads to an awkward migration later (rename + read-through). Starting with `V1` makes the intent explicit in the key itself.

### 9. Store-non-empty branch writes the flag

**Decision:** When Gate A is open (flag unset) but Gate B is closed (store has at least one budget), write `"seededV1" = true` and return `.skippedStoreNonEmptyFlagSealed`. Do not touch the store.

**Why:** This is the "reinstall on a synced device with CloudKit ahead of KV" branch. The user already has their budgets; we must not seed. But we also must not leave Gate A open, because the user could later delete all budgets and we would then reseed (violating F-2.06's "deleting all budgets later does not auto-reseed"). Writing the flag now forward-seals against that. The observable effect on a freshly-installed synced device: nothing changes visually (budgets were already there), and the flag is authoritatively written locally and pushed to iCloud.

**Alternative considered:** Leave the flag unset and rely on KV sync to eventually write it. Rejected: depending on KV sync to eventually converge is exactly the fragility we're trying to avoid, and a user who deletes all their budgets in the meantime would get reseeded.

## Risks / Trade-offs

- **[Very first launch with a pristine iCloud account: seeder runs, pushes `"Food"` to CloudKit, which then syncs to a second device before that device's own seeder runs.]** → Good. The second device's Gate B will be closed by the synced `"Food"` record; Gate A will also close as soon as KV syncs. In the narrow race where Gate B is closed but Gate A is still open on the second device, Decision #9 forward-seals the flag. No duplicates.

- **[First launch with a *fresh* iCloud account on the second device where CloudKit syncs slowly and KV does too.]** → Worst realistic case: both devices' first launches happen within a few seconds, both see both gates open, both seed. The second device's `"Food"` is created as a separate `CKRecord` with a distinct `UUID`. Result: two `"Food"` budgets visible after sync. Acceptable per F-2.06's "at least one Budget" wording; user can delete the duplicate with swipe-to-delete (F-2.01). Noted but not mitigated: serializing first-launch seeding across devices would require a CloudKit-level mutex or unique constraint, neither of which SwiftData+CloudKit supports cleanly (`@Attribute(.unique)` is local-only per tech-design §4.3). Given how rare simultaneous first launch across devices is, and how recoverable the outcome is, the cost of a cross-device mutex is not justified.

- **[`.task` on `ContentView` fires on every view-identity change, not just first launch.]** → Mitigated by the two-gate check: on any call after the first successful seed, Gate A is closed immediately (O(1) KV read) and the method returns `.skippedFlagAlreadySet` before touching SwiftData. No performance concern.

- **[Crash between `context.save()` success and `store.set(..., forKey:)` / `synchronize()`.]** → Covered by Decision #2 and #9. Next launch: Gate A open, Gate B closed (the Budget was saved), takes the forward-seal branch, writes the flag, does not reseed.

- **[Failure mode: `context.save()` throws.]** → The seeder re-throws; `ContentView.task` swallows via `try?`; Gates remain as-found for the next launch. If Gate A was open and Gate B was open, both stay open; next launch retries the full seed. If Gate B was closed when we were called (write-flag-only branch), the `save()` doesn't happen — only the flag write does — so this failure mode applies only to the "seed + save + flag" branch.

- **[`try?` at the call site means silent failures in production.]** → Acceptable and consistent with the rest of the app's eager write paths. A future change can add a debug log or breadcrumb without changing the public API.

- **[Key-value store full (1 MB / 1024 keys limit from tech-design §4.5).]** → `"seededV1"` is a single `Bool`; negligible. No new risk.

- **[Re-seeding a future version of the app with a new "starter budget" requires a new key (`"seededV2"`).]** → Intended. Noted in Decision #8 as the future escape hatch.

## Migration Plan

No data migration. This is a new feature on an unshipped app; all existing installs in this repo are developer builds. The first shipping build's first launch is the first invocation of the seeder; no pre-existing `"seededV1"` value is expected anywhere. For developer builds that already have budgets from manual testing, the first launch after this change lands will hit the forward-seal branch (Decision #9) and write `"seededV1"` without reseeding.

If a future change wants to force a reseed on already-installed devices, it can either:

- Introduce a new key (`"seededV2"`) with its own gate logic, leaving `"seededV1"` alone, OR
- Explicitly clear `"seededV1"` from the KV store as a one-time migration task.

Neither is part of this change.

## Open Questions

- None blocking. Two minor follow-ups, deferred:
  - Should the seeder set `createdAt`/`lastModified` from the injected `now` parameter rather than letting `Budget.init` and `Budget`'s stored default pick `Date()`? Currently `Budget.init` doesn't expose these, so the seed gets the current wall-clock regardless. A later refactor could make tests more deterministic here, but current tests don't depend on it.
  - A debug-only `FirstRunSeeder.reset()` helper that clears `"seededV1"` and optionally deletes the seed budget, for QA flows. Not needed for F-2.06; easy to add later.

## Doc alignment

- **Aligned** with `docs/main-prd.md` — no global constraints or §6.7 rules are affected. The seeded Budget obeys all existing product constraints (currency, carry-over, period).
- **Aligned** with `docs/product-features-planning.md` §F-2.06 — field values (`name: "Food"`, daily, allocation 25, weekly reset cadence, locale currency default) and the "seed runs once / deleting all budgets later does not auto-reseed" requirement are implemented by Decisions #1–#2 and #6.
- **Aligned** with `docs/product-features-planning.md` §F-2.03 — the seeder uses the same defaults as the Add/Edit Budget screen (`Budget.init` defaults for `currencyCode`, `sortOrder` via `Budget.nextSortOrder(for:)`, `isCarryOverEnabled` from `AppSettings.defaultCarryOverEnabled`).
- **Aligned** with `docs/tech-design-doc.md` §4.5 — `"seededV1"` is stored in `NSUbiquitousKeyValueStore`, uses the protocol-abstracted `KeyValueStore` for testability, respects the "no `register(defaults:)` equivalent" rule by checking key existence explicitly, and does not depend on external-change notifications (the flag is write-once-ish; its value is only read, never re-written after being set).
- **Aligned** with `docs/tech-design-doc.md` §5.3 — pure-ish namespace service in `App/`, with injected dependencies; fully unit-testable without SwiftUI, using the existing in-memory `ModelContainer` helper and `MockKeyValueStore`.
- **Update needed after implementation**: `docs/tech-design-doc.md` — add a short subsection documenting `FirstRunSeeder`, the two-gate decision, the `"seededV1"` KV key, and the `.task` wiring in `ContentView`. Likely a new §5.5 or an addendum to §4.5. No updates required for `docs/main-prd.md` or `docs/product-features-planning.md`.
