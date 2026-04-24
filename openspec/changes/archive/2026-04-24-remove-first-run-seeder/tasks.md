## 1. Remove seeder production code

- [x] 1.1 Delete `simple-recurring-budgets/App/FirstRunSeeder.swift` (the whole file, including `SeedResult` and `firstRunSeededV1Key`).
- [x] 1.2 In `simple-recurring-budgets/App/simple_recurring_budgetsApp.swift`, remove the entire `.task { let result = try? await FirstRunSeeder.seedIfNeeded(...); switch result { ... } }` block and replace it with a single-line `.task { analytics.track(AnalyticsEvent.appLaunched) }` (per design Decision 5).
- [x] 1.3 In the same file, remove any now-unused imports or references (`FirstRunSeeder`, `NSUbiquitousKeyValueStore` usage that only served the seeder); keep `import SwiftData` since `sharedModelContainer` still needs it.
- [x] 1.4 Confirm via grep that no production-code references to `FirstRunSeeder`, `seededV1`, `firstRunSeededV1Key`, or `SeedResult` remain outside this change's OpenSpec directory and `docs/`.

## 2. Remove seeder analytics events

- [x] 2.1 In `simple-recurring-budgets/Logging/AnalyticsClient.swift`, delete the three constants `firstRunSeeded`, `firstRunSkipped`, and `firstRunError` from `AnalyticsEvent` (lines 69–71 today). Do not touch `appLaunched` or any other event.
- [x] 2.2 Leave the `.bootstrap` analytics channel untouched if it has other callers; verify via grep. If the channel has no other callers after 2.1, remove the channel case from its enum as well (same PR); otherwise leave it alone.

## 3. Remove seeder tests

- [x] 3.1 Delete `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift` (the whole file, including `SpyKeyValueStore`).
- [x] 3.2 In `simple-recurring-budgetsTests/Logging/AnalyticsClientTests.swift`, remove only the three `#expect(AnalyticsEvent.firstRun...)` assertions at lines 192–194 (today). Leave every other event-name assertion intact.
- [x] 3.3 Confirm via grep that no test references to `FirstRunSeeder`, `firstRunSeeded`, `firstRunSkipped`, `firstRunError`, `SeedResult`, or `seededV1` remain.

## 4. Supersede the prior OpenSpec change

- [x] 4.1 Delete `openspec/changes/add-first-run-seeder/` (entire directory, recursive). This is the "supersede by deletion" step described in design Decision 2.
- [x] 4.2 Run `openspec list --json` and confirm that `add-first-run-seeder` no longer appears and `remove-first-run-seeder` is the only active change touching first-run behavior.
- [x] 4.3 Run `openspec validate remove-first-run-seeder --strict` (or the project's standard validator) and resolve any issues before proceeding.

## 5. Update `docs/tech-design-doc.md`

- [x] 5.1 In §4.5 ("Keys in use" KV table), remove the `"seededV1"` row.
- [x] 5.2 Immediately after the §4.5 KV key table (or in a short note paragraph that follows it), add one line: `The string "seededV1" was used by a prior first-run seeder and is now orphaned on upgraded installs. It SHALL NOT be reused as a new KV key; the "V1" suffix remains reserved per the original convention so any future one-time-reseed change introduces a distinct key name.`
- [x] 5.3 Delete §4.6 ("First-Run Bootstrap (FirstRunSeeder)") in its entirety.
- [x] 5.4 Delete §5.5 ("Bootstrap") in its entirety. If §5 has subsequent subsections that reference §5.5 by number, re-number or drop the cross-references.
- [x] 5.5 Add a new version-history row at the bottom of the doc (after the current `0.5` row) capturing the removal. Suggested text: `| 0.6 | <YYYY-MM-DD> | Jimmy Ho | Remove §4.6 (FirstRunSeeder) and §5.5 (Bootstrap); drop "seededV1" from §4.5 KV key table; note orphaned-key status; see change remove-first-run-seeder |`.

## 6. Update `docs/product-features-planning.md`

- [x] 6.1 Replace the existing F-2.06 block ("First-run seed and empty state") with the wording specified verbatim in `design.md` → Decision 4 ("First-run empty state" version). Preserve the section header depth (`#####`) and surrounding whitespace.
- [x] 6.2 Scan the rest of the doc for any cross-reference to "first-run seed", "Food" (as a seed example), or the F-2.06 acceptance criteria wording from before, and update or remove them for consistency.

## 7. Verify `docs/main-prd.md` needs no changes

- [x] 7.1 Grep `docs/main-prd.md` for "seed", "Food", "F-2.06". Confirm no updates are required. (If any match appears, add a follow-up sub-task to update it; otherwise mark this section done as documentation of the negative result.)

## 8. Build, test, and smoke-check

- [x] 8.1 Run `make test` (or `bash scripts/test.sh`) from the repo root per AGENTS.md and `.cursor/rules/ios-build-test.mdc`. Expect the FirstRunSeeder suite and three `firstRun.*` assertions to be gone; all remaining tests SHALL pass.
- [ ] 8.2 Launch the app in a simulator with a fresh container (wipe the simulator data or use a clean simulator). Verify that on first launch the `ContentView` placeholder renders with no seeded Budget in any list / persistence inspection. Verify that closing and relaunching does not insert a Budget either.
- [ ] 8.3 Verify via Xcode's SwiftData inspector (or a simple in-app log during smoke testing) that `NSUbiquitousKeyValueStore.default.object(forKey: "seededV1")` is untouched by this build (no read, no write), consistent with design Decision 3.

## 9. Archive this change

- [ ] 9.1 After all sections 1–8 are complete and `make test` passes, run `openspec archive remove-first-run-seeder` (or follow the project's `openspec-archive-change` skill). Because this change adds no new main-spec capability and explicitly supersedes a pending change by deletion, expect the archive step to move this change's directory into `openspec/changes/archive/` without creating any new `openspec/specs/first-run-seed/` directory.
- [ ] 9.2 After archive, confirm: (a) `openspec/specs/` contains no `first-run-seed/` directory; (b) `openspec/changes/` contains no `add-first-run-seeder/` and no `remove-first-run-seeder/`; (c) `openspec/changes/archive/` contains `remove-first-run-seeder/` (with whatever date prefix the archive step applies); (d) `openspec/changes/archive/add-first-run-seeder/` does NOT exist (the prior change was deleted, not archived).
