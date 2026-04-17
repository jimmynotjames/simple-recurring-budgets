## 1. Service — Scaffolding

- [x] 1.1 Create `simple-recurring-budgets/App/FirstRunSeeder.swift` with a caseless `enum FirstRunSeeder` and a nested `enum SeedResult { case seeded, skippedFlagAlreadySet, skippedStoreNonEmpty, skippedStoreNonEmptyFlagSealed }`.
- [x] 1.2 Add `static let firstRunSeededV1Key = "seededV1"` on `FirstRunSeeder` and document its purpose (single-version first-run flag; future force-reseeds use a new key).

## 2. Service — Implementation

- [x] 2.1 Add the entry point `@discardableResult static func seedIfNeeded(context: ModelContext, store: KeyValueStore, isCarryOverEnabled: Bool, now: Date = Date()) async throws -> SeedResult`.
- [x] 2.2 Gate A: if `store.object(forKey: firstRunSeededV1Key) != nil`, return `.skippedFlagAlreadySet` immediately without reading the store count.
- [x] 2.3 Gate B: call `try context.fetchCount(FetchDescriptor<Budget>())`. If `> 0`, write `store.set(true, forKey: firstRunSeededV1Key)` and `_ = store.synchronize()`, then return `.skippedStoreNonEmptyFlagSealed` (forward-seal branch per design Decision #9).
- [x] 2.4 Both gates open: construct the seed with `Budget(name: "Food", allocation: 25, period: .daily, resetCadence: .weekly, isCarryOverEnabled: isCarryOverEnabled)`; do **not** pass `currencyCode` (let `Budget.init` default to locale/USD).
- [x] 2.5 Set `budget.sortOrder = try Budget.nextSortOrder(for: context)` before `context.insert(budget)`.
- [x] 2.6 Call `try context.save()`. If it throws, rethrow without writing the flag.
- [x] 2.7 After `save()` succeeds, call `store.set(true, forKey: firstRunSeededV1Key)` and `_ = store.synchronize()`, then return `.seeded`.
- [x] 2.8 Ensure the method is documented with a doc comment summarizing the two-gate decision, the flag-write ordering, and the link to F-2.06 and tech-design §4.5.

## 3. Wiring — ContentView

- [x] 3.1 In `simple-recurring-budgets/Views/ContentView.swift`, add `@Environment(\.modelContext) private var modelContext` and `@Environment(AppSettings.self) private var settings`.
- [x] 3.2 Attach a `.task` modifier on the Budgets root (the placeholder content inside `NavigationStack`'s root) that calls `try? await FirstRunSeeder.seedIfNeeded(context: modelContext, store: NSUbiquitousKeyValueStore.default, isCarryOverEnabled: settings.defaultCarryOverEnabled)`.
- [x] 3.3 Confirm `#Preview { ContentView() }` still compiles; add an `.environment(AppSettings(store: MockKeyValueStore()))` injection to the preview if needed so the preview does not touch iCloud.

## 4. Tests — Setup

- [x] 4.1 Create `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift` using the Swift Testing framework (`import Testing`).
- [x] 4.2 Reuse the existing in-memory `ModelContainer` helper in `simple-recurring-budgetsTests/Helpers/TestModelContainer.swift` for a `ModelContext` per test.
- [x] 4.3 Use `MockKeyValueStore` from `Settings/KeyValueStore.swift` for the `store` parameter; construct a fresh one per test.

## 5. Tests — Gate behavior

- [x] 5.1 Test `.skippedFlagAlreadySet`: pre-seed `store.set(true, forKey: "seededV1")`; call `seedIfNeeded`; assert the result is `.skippedFlagAlreadySet`, no `Budget` was inserted, and `context.hasChanges == false`.
- [x] 5.2 Test `.skippedFlagAlreadySet` short-circuit: verify the service does not call `fetchCount` — e.g., pre-insert a `Budget` into the context and assert the call returns `.skippedFlagAlreadySet` without mutating the flag or the store (the `Budget` is still there, the flag is still `true`, no extra inserts).
- [x] 5.3 Test `.skippedStoreNonEmptyFlagSealed`: leave the flag unset; insert a pre-existing `Budget` via `context.insert` + `context.save()`; call `seedIfNeeded`; assert the result is `.skippedStoreNonEmptyFlagSealed`, the store still has exactly one `Budget`, and `store.object(forKey: "seededV1") != nil` after the call.
- [x] 5.4 Test "both gates open → `.seeded`": empty store, unset flag; call `seedIfNeeded` with `isCarryOverEnabled: true`; assert the result is `.seeded`, exactly one `Budget` exists in the store, and the flag is now set.

## 6. Tests — Seed field values

- [x] 6.1 Assert the seeded `Budget` fields: `name == "Food"`, `allocation == Decimal(25)`, `period == BudgetPeriod.daily.rawValue`, `resetCadence == ResetCadence.weekly.rawValue`, `isCarryOverEnabled == true` (when passed `true`).
- [x] 6.2 Assert `currencyCode == Locale.current.currency?.identifier ?? "USD"` (matches `Budget.init` default without explicit override).
- [x] 6.3 Assert `sortOrder == 0` (since the store was empty immediately before insert, `Budget.nextSortOrder(for:)` returns `0`).
- [x] 6.4 Parameterize `isCarryOverEnabled`: call with `false` and assert the inserted `Budget.isCarryOverEnabled` is `false`.

## 7. Tests — Ordering and error handling

- [x] 7.1 Success ordering: after `.seeded`, assert `store.object(forKey: "seededV1") as? Bool == true` and that the `Budget` is fetchable (i.e., `save()` preceded the flag write). Document in the test that observing ordering directly is not possible; inspecting both post-conditions and the documented implementation order is the proxy.
- [x] 7.2 Save-failure path: DEFERRED — save-failure injection is infeasible without new test scaffolding. See file-header comment in FirstRunSeederTests.swift. Covered by task 7.3.
- [x] 7.3 Alternate save-failure coverage (if 7.2 is deferred): add a targeted test that directly verifies the call *sequence* by using a `KeyValueStore` test double that records each `set(_:forKey:)` and `synchronize()` call; assert that when `.seeded` is returned, the `set("seededV1", true)` call was recorded exactly once and after `Budget` insertion was visible in `context.fetchCount`.

## 8. Tests — Idempotency

- [x] 8.1 Call `seedIfNeeded` twice in sequence on the same `context` and `store` with both gates initially open. Assert the first returns `.seeded`, the second returns `.skippedFlagAlreadySet`, and exactly one `Budget` exists after both calls.
- [x] 8.2 Concurrent-call simulation: call `seedIfNeeded` twice in an `async let` pair on the same `context`/`store`. Assert that at most one `.seeded` is returned (the other is `.skippedFlagAlreadySet` or `.skippedStoreNonEmptyFlagSealed`) and the store contains exactly one seed `Budget`. Note: SwiftData `ModelContext` is not thread-safe; if the test helper does not support concurrent usage, replace with a sequential double-call test and document the limitation in a test comment.

## 9. Tests — Post-forward-seal behavior

- [x] 9.1 Forward-seal durability: execute the `.skippedStoreNonEmptyFlagSealed` path, then delete every `Budget` from the context and save. Call `seedIfNeeded` again; assert the result is `.skippedFlagAlreadySet` and no new `Budget` is inserted (F-2.06 "deleting all budgets later does not auto-reseed").

## 10. Documentation

- [x] 10.1 Update `docs/tech-design-doc.md` — add a short subsection (likely addendum to §4.5, or a new §5.5 "Bootstrap") documenting: the `FirstRunSeeder` service, the `"seededV1"` KV key added to the list of iCloud KV keys used by the app, the two-gate decision, and the `.task` wiring in `ContentView`.
- [x] 10.2 Confirm no changes are needed in `docs/product-features-planning.md` (F-2.06 acceptance criteria are implemented, not altered) or `docs/main-prd.md` (no global rules affected). Note the confirmation in the PR description or change archive.

## 11. Validation

- [x] 11.1 Build the app (iOS Simulator target) and launch it with a clean container: verify a single "Food" budget appears on the Budgets root placeholder, the flag is persisted (a second launch shows no new seed), and manually deleting the budget and relaunching does not cause a reseed.
- [x] 11.2 Run all existing tests to verify no regressions in `AppSettings`, `Budget`, or lifecycle tests from the `.task` wiring or the new file.
- [x] 11.3 Run the new `FirstRunSeederTests` suite and confirm every scenario in `openspec/changes/add-first-run-seeder/specs/first-run-seed/spec.md` has at least one passing test.
