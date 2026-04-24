## Context

`App/FirstRunSeeder.swift` was introduced under change `add-first-run-seeder` to insert a single placeholder `"Food"` Budget on first launch. The seeder implements a two-gate decision (iCloud KV flag `"seededV1"` + SwiftData `Budget` fetch count) with forward-sealing, strict save-before-flag-write ordering, and dedicated analytics events (`firstRun.seeded`, `firstRun.skipped`, `firstRun.error`). It is wired from `simple_recurring_budgetsApp`'s `WindowGroup` via `.task`, using `sharedModelContainer.mainContext`, `NSUbiquitousKeyValueStore.default`, and `AppSettings.defaultCarryOverEnabled`.

The `add-first-run-seeder` change is marked complete in `openspec list --json` (35/35 tasks) but has **never been archived**. Its delta spec at `openspec/changes/add-first-run-seeder/specs/first-run-seed/spec.md` has not propagated into `openspec/specs/`, and there is no `openspec/specs/first-run-seed/` directory today.

Current doc touchpoints for the seeder:
- `docs/product-features-planning.md` §F-2.06 ("First-run seed and empty state") — mandates the `"Food"` seed with daily / allocation 25 / weekly reset cadence.
- `docs/tech-design-doc.md` §4.5 (KV key table includes `"seededV1"`), §4.6 ("First-Run Bootstrap (FirstRunSeeder)"), §5.5 ("Bootstrap").
- `docs/main-prd.md` — no direct references.

Constraints:
- **CloudKit**: `NSUbiquitousKeyValueStore` offers no durable "delete across all devices" primitive for a single key that would complete faster than the feature being retired; installs that already synced `"seededV1" = true` will continue to have it in the KV store until they next sign out of iCloud or reset KV state.
- **No spec-level churn**: the `first-run-seed` capability never reached `openspec/specs/`, so there is no main-spec REMOVED delta to emit.
- **Audit trail**: the prior change should not be silently erased; its rationale (and the reversal) must be discoverable from the repo history.

## Goals / Non-Goals

**Goals:**

- Remove the seeder and its entire support surface (service, wiring, tests, analytics events, iCloud KV key read/write, OpenSpec change directory, and all three doc sections) in one coherent change.
- Leave the app's first-launch state as "empty store + whatever the current `ContentView` renders" — no seeded Budget, no new placeholder, no alternative onboarding flow introduced here.
- Preserve `AppSettings`, `KeyValueStore`, and `AnalyticsClient` public API surface (no breaking changes to those modules).
- Keep a single `AnalyticsEvent.appLaunched` track firing once per launch after removal, so we don't lose the "did launch" signal that the seeder's `.task` currently hosts.
- Leave the repo in a state where `openspec list` contains only this change (the prior `add-first-run-seeder` is gone) and the `first-run-seed` capability is not present in `openspec/specs/`.

**Non-Goals:**

- Designing an empty-state UX for the Budgets screen. That belongs to F-2.01 (real Budgets screen) and is out of scope here — today's `ContentView` remains a placeholder.
- Cleaning up the `"seededV1"` KV key value on devices that already wrote `true` there. See risks below.
- Any change to Budget math, lifecycle orchestration, migrations, schema, or CloudKit record layout.
- Back-porting or archiving `add-first-run-seeder` into `openspec/specs/` before deletion. We do not want a `first-run-seed` capability to briefly exist in main specs only to be immediately removed (see Decision 2).
- Introducing a new "bootstrap" module or `AppBootstrap` namespace to replace the seeder. "No bootstrap" is the design.

## Decisions

### Decision 1: Delete `FirstRunSeeder` outright rather than neutering it

**Choice:** Remove `App/FirstRunSeeder.swift` and `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift` entirely.

**Alternatives considered:**

- **Gut the body, keep the type.** Reduce `seedIfNeeded` to `return .skippedFlagAlreadySet` and keep the `FirstRunSeeder` enum, `SeedResult`, and tests. Rejected: leaves dead code and misleading types (a `SeedResult.seeded` case that can never be returned), and the next developer touching it would have to re-learn why the no-op exists.
- **Replace with `AppBootstrap` namespace.** Introduce a new empty-but-extensible type. Rejected: speculative abstraction; we have no second bootstrap caller. If a future change needs launch-time hooks, it can introduce the namespace then with a concrete caller.

**Rationale:** The seeder's entire reason to exist was the seed. Removing the seed removes the only requirement it serves. An empty file is clearer than an empty service.

### Decision 2: Do not archive `add-first-run-seeder` before removing it

**Choice:** Delete `openspec/changes/add-first-run-seeder/` directly as a task in this change, without first running archive.

**Alternatives considered:**

- **Archive then REMOVE.** Run `openspec archive add-first-run-seeder` to propagate its delta into `openspec/specs/first-run-seed/`, then emit a REMOVED-capability delta in this change. Rejected: this creates a main-spec capability purely so we can immediately delete it; the resulting git history (`specs/first-run-seed/` appears in one commit and disappears in the next) is worse audit signal than a single commit that cleanly deletes the pending change.
- **Leave the pending change in place.** Keep `add-first-run-seeder` as a historical artifact. Rejected: `openspec list` would keep showing it as a complete-but-unarchived change, implying its implementation is live; that contradicts reality once this change lands.

**Rationale:** The `add-first-run-seeder` change represents a decision we are reversing before it formally entered the main spec set. Deleting its directory is the most accurate representation of "this capability never landed." The audit trail lives in git history (both directories will appear in `git log -- openspec/changes/`).

### Decision 3: Do not clean up existing `"seededV1"` KV values

**Choice:** Stop reading `"seededV1"`; do not write `removeObject(forKey:)` or `set(false, forKey:)` on existing installs.

**Alternatives considered:**

- **Migration that removes the key.** Add a one-shot launch-time `NSUbiquitousKeyValueStore.default.removeObject(forKey: "seededV1")` call. Rejected: this re-introduces a launch-time side effect (exactly the thing we are removing), and the KV quota per-app (1 MB / 1024 keys) makes one leftover `Bool` irrelevant.
- **Rename the key.** Not applicable — nothing is being added in its place.

**Rationale:** The value is write-once-and-forget; the app no longer reads it; leaving it in place is cheaper than any cleanup path and has no user-visible effect.

**Follow-up:** add a short note to `docs/tech-design-doc.md` §4.5 stating that `"seededV1"` is an orphaned key on upgraded installs and must not be reused for a different purpose (matching the existing rule that `V1` in the key name reserves `V2` for any future reseed).

### Decision 4: Rewrite F-2.06 as "First-run empty state" rather than deleting it

**Choice:** Keep F-2.06 as a feature entry but rewrite it so the acceptance criteria describe an empty-state experience on the Budgets screen (no seed). Explicitly link the responsibility to F-2.01 (real Budgets screen) for the actual UI.

**Alternatives considered:**

- **Delete F-2.06 entirely.** Reject because feature IDs are referenced elsewhere (e.g., in the existing `add-first-run-seeder` proposal and design). Reusing or gapping an ID is worse than repurposing it.
- **Mark F-2.06 `Status: Cancelled`.** Rejected for the same reason as deletion, and because the empty-state requirement is still a real product requirement — it just does not require a seed.

**Rationale:** We still care that first launch doesn't drop the user into a featureless screen; we just no longer care that "the screen is non-empty because the app inserted something." The empty-state requirement is a genuine user-facing contract that belongs in the feature catalog.

**Exact wording** (to be applied verbatim in the implementation task):

> ##### F-2.06: First-run empty state
>
> - **Status:** Open
> - **Description:** On first launch when the data store contains no budgets, the **Budgets screen** displays a first-run empty state with a clear primary action to create a budget. No placeholder or seed Budget is inserted by the app.
> - **Acceptance Criteria:**
>   - After first launch with an empty store, the **Budgets screen** shows its empty-state view (title, short description, and a primary "Create a budget" CTA) — NOT a blank or unlabeled screen.
>   - No `Budget` entity is created by the app as part of launch; any Budget in the store was created by the user.
>   - The empty state is equivalent to the empty state shown after the user deletes all their budgets.
> - **Edge Cases / Notes:** The empty-state UI itself ships under F-2.01; F-2.06 is the first-launch contract.
> - **Dependencies:** F-2.01

### Decision 5: Collapse the seeder `.task` to a single-line `appLaunched` track

**Choice:** In `simple_recurring_budgetsApp.swift`, replace the current `.task { let result = try? await FirstRunSeeder.seedIfNeeded(...); switch result { ... }; analytics.track(AnalyticsEvent.appLaunched) }` with `.task { analytics.track(AnalyticsEvent.appLaunched) }`.

**Alternatives considered:**

- **Remove the `.task` entirely.** Rejected: `appLaunched` is a useful signal for analytics and the current code fires it from inside the same task. Preserving one-launch-one-event semantics is cheaper than moving the track elsewhere.
- **Fire `appLaunched` from `init()`.** Rejected: `init` runs before SwiftUI has fully mounted the scene, and our analytics client is `@State`; keeping the track in `.task` preserves the current firing point.

**Rationale:** Minimal residual surface. The `.task` modifier is already attached to `ContentView` in the `WindowGroup` and currently uses the same captures (`analytics`), so the edit is a block-to-one-liner shrink.

## Risks / Trade-offs

- **[First-launch regression with no replacement screen yet]** → Until F-2.01 ships its real empty state, first launch will show `ContentView`'s current placeholder content with no seeded data. Mitigation: `ContentView` is already a placeholder today and was never shipped; the rewritten F-2.06 explicitly ties the empty-state UX to F-2.01's delivery. Non-issue for the current TestFlight audience (internal only) but worth calling out in the task list as a doc note.
- **[Users who already received the seed on the current build]** → They will keep their seeded `"Food"` Budget (the app no longer touches it, and CloudKit will not delete records we don't delete). It will behave as any user-authored Budget — editable and deletable. Mitigation: none needed; this matches the "no auto-reseed after delete" contract F-2.06 always implied.
- **[Orphaned `"seededV1"` KV value]** → Harmless per Decision 3, but a future developer might see the key in CloudKit KV diagnostics and wonder. Mitigation: the note added to `docs/tech-design-doc.md` §4.5 documents the orphaned status and the "reserved — don't reuse" rule.
- **[`openspec list` will show no live change about first-run seeding]** → Correct, but anyone reading older commits or the archive will see `add-first-run-seeder` and assume it shipped. Mitigation: this change's proposal and design explicitly document the reversal; the commit that lands this change deletes the prior change directory, making the reversal discoverable via `git log`.
- **[Analytics dashboards depending on `firstRun.*` events]** → None known; the events were only emitted from the seeder and its tests. Mitigation: grep confirms no other callers. A Datadog / whatever-dashboard audit is a one-line follow-up if such a dashboard exists off-repo, but not blocking.
- **[Conflict with docs/tech-design-doc.md and docs/product-features-planning.md]** → Called out in the proposal's Doc alignment section and resolved by this change's tasks (doc edits are in scope, not deferred).

## Migration Plan

1. Land this change (single PR), which:
   - Deletes `App/FirstRunSeeder.swift` and `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift`.
   - Collapses the `.task` in `simple_recurring_budgetsApp.swift`.
   - Removes the three `firstRun.*` constants from `Logging/AnalyticsClient.swift` and their test assertions.
   - Deletes `openspec/changes/add-first-run-seeder/`.
   - Rewrites `docs/product-features-planning.md` §F-2.06, trims `docs/tech-design-doc.md` §§4.5 / 4.6 / 5.5, and bumps the tech-design version history.
2. No staged rollout needed (no backend, no feature flag). The change is binary: next build does not seed, previous builds did seed.
3. **Rollback strategy:** if the removal needs to be reverted (e.g., F-2.01 slips and an empty placeholder screen is unacceptable for TestFlight), revert the single PR. The seeder's full history (including its own tests and delta spec) is preserved in git and can be restored cleanly. The `"seededV1"` flag semantics on any device that ran the reverted build remain compatible with the restored seeder because the key format and version (`V1`) are unchanged.
4. No data migration. No CloudKit record cleanup.

## Open Questions

_(none — decisions 1 through 5 cover the implementation shape; remaining choices are mechanical.)_
