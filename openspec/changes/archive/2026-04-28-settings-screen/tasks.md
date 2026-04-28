## 1. Pre-implementation gates

- [x] 1.1 Get user approval on the three new English source strings for the iCloud "Sync paused / local only" row variant: row label (proposed: `"iCloud Sync Paused"`), accessibility label (proposed: `"iCloud sync is paused. Your budgets are saved on this device but not syncing to other devices."`), and section footer (proposed: `"Your budgets are saved on this device only. Restart the app to retry iCloud sync."`). No string-catalog or implementation work for the `paused` row begins until this is resolved. (See design.md Decision 6.)
- [x] 1.2 Re-confirm copy-frozen scope: every other localized string referenced by the spec stays verbatim from the current `SettingsView.swift` and `Localizable.xcstrings`, including the `"Sign in to iCloud in Settings…"` footer and the `"Change Start of Week?"` alert title. **Exception:** the Currency Display picker examples (`"$25"`, `"USD 25"`, `"USD $25"`) are intentionally lifted from the freeze and are replaced by locale-aware live previews per Decision 1; this is the only en_US-literal example string set being changed in this task group.

## 2. CurrencyDisplayPreference type extraction

- [x] 2.1 Create `simple-recurring-budgets/Formatting/CurrencyDisplayPreference.swift`. Move the enum out of `SettingsView.swift`; promote from `fileprivate` to `internal`; add `String` raw values (`"symbol"`, `"code"`, `"codeAndSymbol"`); preserve `CaseIterable`, `Identifiable (id: Self)`, `Codable`, and add `Sendable`.
- [x] 2.2 Carry over the existing localized `label` strings verbatim (keys `settings.currencyDisplay.symbol`, `settings.currencyDisplay.code`, `settings.currencyDisplay.codeAndSymbol`). **Replace** the existing hard-coded `var example: String` (currently returns `"$25"` / `"USD 25"` / `"USD $25"`) with `func example(locale: Locale = .autoupdatingCurrent) -> String` that resolves `locale.currency?.identifier ?? "USD"` and returns `Decimal(25).formatted(currencyCode: code, display: self, locale: locale)`.
- [x] 2.3 Delete the old `fileprivate enum CurrencyDisplayPreference` block from `SettingsView.swift`. No call-site changes yet — the picker still binds to local `@State` until step 4.

## 3. AppSettings — currencyDisplay persistence and sync

- [x] 3.1 In `simple-recurring-budgets/Settings/KeyValueStore.swift`, add `func set(_ value: String, forKey defaultName: String)` to the `KeyValueStore` protocol. Implement it on `MockKeyValueStore` (mirroring the existing `Bool` / `Int64` storage pattern). `NSUbiquitousKeyValueStore` already supports `String` natively — verify the protocol extension picks it up; add an explicit shim only if the compiler requires one.
- [x] 3.2 In `simple-recurring-budgets/Settings/AppSettings.swift`, add `static let currencyDisplayKey = "currencyDisplay"` next to the existing key constants.
- [x] 3.3 Add the stored property `var currencyDisplay: CurrencyDisplayPreference` with `didSet` mirroring the `defaultCarryOverEnabled` / `weekStartDay` pattern (skip writes when `isApplyingFromStore`; otherwise `store.set(currencyDisplay.rawValue, forKey: Self.currencyDisplayKey)` then `_ = store.synchronize()`).
- [x] 3.4 Add a private `static func readCurrencyDisplay(from store: KeyValueStore) -> CurrencyDisplayPreference` that returns `.symbol` for missing entries, parses `String` raw values, and falls back to `.symbol` for unrecognized values without overwriting them.
- [x] 3.5 Initialize `currencyDisplay` in `init(store:)` via `Self.readCurrencyDisplay(from: store)`.
- [x] 3.6 Extend `applyKeys(_:)` to handle `Self.currencyDisplayKey` (re-read inside the `isApplyingFromStore` window).
- [x] 3.7 Extend `reloadAllFromStore()` to include `currencyDisplayKey` in its key set.

## 4. SettingsView — bind picker to AppSettings.currencyDisplay

- [x] 4.1 Remove the `@State private var currencyDisplay: CurrencyDisplayPreference` stub from `SettingsView`.
- [x] 4.2 Update the `displaySection` picker `selection:` argument to bind to `$settings.currencyDisplay` (using the existing `@Bindable var settings = settings` pattern in `body`).
- [x] 4.3 Verify the row format is preserved as `"\(option.label) — \(option.example())"` (note: `example` is now a function call; pass no arguments so it picks up the user's `Locale.autoupdatingCurrent`). Confirm the `label` strings still load correctly and that the example reflects the device's locale (run a manual smoke check with the simulator set to e.g. fr_FR and ja_JP).

## 5. Formatters — Decimal.formatted display extension

- [x] 5.1 In `simple-recurring-budgets/Formatting/Formatters.swift`, extend `Decimal.formatted(currencyCode:locale:)` with a `display: CurrencyDisplayPreference = .symbol` parameter (defaulted, so existing call sites compile unchanged).
- [x] 5.2 Implement the three branches per design.md Decision 2: `.symbol` uses `.currency(code:).locale(locale)`; `.code` uses `.currency(code:).presentation(.isoCode).locale(locale)`; `.codeAndSymbol` composes `"\(currencyCode) \(symbolForm)"` where `symbolForm` is the same formatter result as `.symbol`.
- [x] 5.3 Extend `CarryOverFormatter.display(_:currencyCode:locale:)` with a `display: CurrencyDisplayPreference = .symbol` parameter, threading it through to the underlying `Decimal.formatted(currencyCode:display:locale:)` call.

## 6. Currency Display propagation to render sites

- [x] 6.1 In `BudgetRowView`, thread `settings.currencyDisplay` into both monetary `formatted(currencyCode:…)` calls (the visible `remaining.formatted(...)` and any inside `rowAccessibilityLabel`).
- [x] 6.2 In `BudgetRowView`, thread `settings.currencyDisplay` into the `CarryOverChip` initializer (extend `CarryOverChip` with a new `display: CurrencyDisplayPreference` parameter; the chip does NOT read `@Environment(AppSettings.self)` itself).
- [x] 6.3 In `CarryOverChip`, thread the new `display` parameter into `CarryOverFormatter.display(...)`.
- [x] 6.4 Audit all call sites of `Decimal.formatted(currencyCode:…)` and `CarryOverFormatter.display(...)` in the codebase (search both APIs); document any site that intentionally keeps the `.symbol` default (e.g., test fixtures), so the audit is reviewable in the PR. Test fixtures in `FormattersTests.swift` and `AppSettingsTests.swift` intentionally use the `.symbol` default (explicit `locale: enUS`) for determinism.

## 7. SyncStatus — environment-injected sync availability

- [x] 7.1 Create `simple-recurring-budgets/Sync/SyncStatus.swift` with the `@Observable final class SyncStatus` per design.md Decision 5: `let containerBacking: ContainerBacking` (with cases `.cloudKit`, `.localFallback`); `var accountStatus: AccountStatus` (default `.checking`, with cases `.checking`, `.available`, `.unavailable`); `init(containerBacking:)`.
- [x] 7.2 Add the `RowState` derivation extension on `SyncStatus` (cases `.checking`, `.available`, `.paused`, `.unavailable`) implementing the exact mapping table from the spec.
- [x] 7.3 In `simple_recurring_budgetsApp.swift`, change `makeProductionModelContainer(analytics:)` to return `(ModelContainer, SyncStatus.ContainerBacking)` (or split into a new helper that returns the tuple) — emitting `.cloudKit` for the CloudKit-backed branch and `.localFallback` for the on-disk fallback branch. The fatal-failure branch retains its `fatalError` semantics.
- [x] 7.4 In `simple_recurring_budgetsApp.init()`, build a `SyncStatus` from the returned backing and store it as `@State`.
- [x] 7.5 Inject `SyncStatus` into the SwiftUI environment alongside `AppSettings`, `Router`, and `analytics` in `WindowGroup`'s body.

## 8. SettingsView — iCloud Sync Status row using SyncStatus

- [x] 8.1 Add `@Environment(SyncStatus.self) private var syncStatus` to `SettingsView`.
- [x] 8.2 Delete `fileprivate enum ICloudSyncStatus` and the `@State private var iCloudStatus` property.
- [x] 8.3 Replace the `iCloudStatusRow` view-builder switch with a switch over `syncStatus.rowState` (`checking`, `available`, `paused`, `unavailable`).
- [x] 8.4 For the `available` and `unavailable` row variants, preserve the existing localized strings and SF Symbols verbatim.
- [x] 8.5 For the `paused` row variant, render the new SF Symbol (`exclamationmark.icloud` in `.orange`) and the new localized strings approved in task 1.1. Add three new entries to `Localizable.xcstrings` with `comment:` translator notes per `docs/tech-design-doc.md` §5.1: `settings.iCloud.paused`, `settings.iCloud.paused.accessibilityLabel`, `settings.iCloud.paused.footer`.
- [x] 8.6 Update the `iCloudSection` footer logic so the `unavailable` footer copy renders for `rowState == .unavailable` (existing behavior, preserved verbatim) AND the new `paused` footer copy renders for `rowState == .paused`.
- [x] 8.7 Replace `loadICloudStatus()` so it writes the result of `CKContainer.default().accountStatus()` into `syncStatus.accountStatus` rather than a local `@State`. On error, set `syncStatus.accountStatus = .unavailable`.
- [x] 8.8 Add observers (within a `.task` or paired `.onAppear` / `.onDisappear`) for `NSNotification.Name.CKAccountChanged` and `NSUbiquityIdentityDidChange`. On each notification, re-run the account-status query and assign the result to `syncStatus.accountStatus`. Hop to the main actor explicitly (mirror `AppSettings`'s `MainActor.assumeIsolated` pattern). Remove observers cleanly when the view disappears or the task is cancelled.
- [x] 8.9 Update the preview-only init `init(previewICloudStatus:)` to take a `SyncStatus.AccountStatus` (and optionally a `ContainerBacking`) so previews can drive each of the four `rowState` cases. Update existing `#Preview` blocks to use the new signature and add a "Sync paused" preview.

## 9. Tests

- [x] 9.1 Add tests for `CurrencyDisplayPreference`: raw values, `CaseIterable` order, `Identifiable` `id` equality, and `example(locale:)` correctness. The `example(locale:)` tests SHALL: (a) for each case, assert the result equals `Decimal(25).formatted(currencyCode: code, display: case, locale: locale)` for at least `en_US` (USD), `fr_FR` (EUR), `ja_JP` (JPY), and `ar_SA` (SAR); (b) assert the USD fallback path by passing a locale whose `currency?.identifier` is `nil` and checking the result equals the same formula run against `"USD"`; (c) assert the result is **not** the en_US literals `"$25" / "USD 25" / "USD $25"` for non-USD locales.
- [x] 9.2 Add tests for `AppSettings.currencyDisplay`: default `.symbol` on fresh store; persisted value read on init; setter persists raw value; invalid stored value falls back to `.symbol` without overwriting; observable change notification fires; external-change notification with `currencyDisplay` in the changed-keys updates the property; external-change notification with `nil` changed-keys reloads `currencyDisplay`. Use `MockKeyValueStore`.
- [x] 9.3 Add tests for `Decimal.formatted(currencyCode:display:locale:)`: across at least USD (en_US), EUR (fr_FR), JPY (ja_JP), and Arabic (ar_SA), assert the produced string for each `CurrencyDisplayPreference`. For `.codeAndSymbol`, assert that the produced string contains the ISO code, contains the locale-specific symbol form, and uses an ASCII space as the separator.
- [x] 9.4 Add tests for `CarryOverFormatter.display(...)` with the new `display:` parameter — assert the magnitude string respects the preference and the `sign` / `label` semantics are unchanged.
- [x] 9.5 Add tests for `SyncStatus.rowState` mapping covering all five `(containerBacking, accountStatus)` combinations defined in the spec.
- [x] 9.6 Add at least one test (or extend an existing `SettingsView`-related test file, depending on what already exists) that exercises the picker → `AppSettings.currencyDisplay` write path using a hosted `SettingsView` with an injected `MockKeyValueStore` `AppSettings` and a `SyncStatus`. If a hosted SwiftUI test is too heavyweight, replace with a unit test that constructs the equivalent binding inline and asserts the write.
- [x] 9.7 Add a test that exercises the week-start confirmation flow (cancel discards `pendingWeekStart`; confirm commits to `AppSettings.weekStartDay`). Re-use existing test infrastructure if any equivalent test already exists; otherwise create a new file under `simple-recurring-budgetsTests/Views/` per `docs/tech-design-doc.md` §5.3 conventions.
- [x] 9.8 Run the full test suite via `bash scripts/test.sh` (or `make test`) per `.cursor/rules/ios-build-test.mdc`. Fix any regressions before proceeding.

## 10. Doc updates

- [x] 10.1 Update `docs/product-features-planning.md` F-2.05: replace "content blank to start" / "Entry point button is placed in canonical place" with concrete acceptance criteria enumerating the six finalized sections (Budgets default carry-over → cross-reference F-2.07; Calendar week-start with confirmation → cross-reference F-5.01; Display currency-display preference; iCloud Sync Status — tri-state; Support: Send Feedback / Rate the App / Privacy Policy; About: version + build) plus the Done dismissal. Use cross-references (not duplication) to F-2.07 and F-5.01.
- [x] 10.2 Update `docs/tech-design-doc.md` §4.5 KV-key table: add a row for `"currencyDisplay"` (Type: `String` (`CurrencyDisplayPreference.rawValue`); Owner: `AppSettings`; Purpose: `"Currency display format preference for monetary amounts"`).
- [x] 10.3 Update `docs/tech-design-doc.md` §4.5 (or end of §4): add a short paragraph documenting the `SyncStatus` environment value — what it carries (`containerBacking`, `accountStatus`, derived `rowState`), where its `containerBacking` is decided (launch-time `makeProductionModelContainer` outcome), and how screens consume it via `@Environment(SyncStatus.self)`.
- [x] 10.4 Update `docs/tech-design-doc.md` Revision History (Appendix B): add a new row for this change with a one-line summary (e.g., "Add §4.5 KV-key row for `currencyDisplay`; document `SyncStatus` environment plumbing").
- [x] 10.5 Confirm `docs/main-prd.md` requires no edits for this change (per design.md "Doc alignment" — Settings UX details are below PRD altitude). If the verifier disagrees, raise it before archive.

## 11. Verification and archive

- [x] 11.1 Run `openspec verify settings-screen` (or equivalent) and resolve any drift between specs / proposal / design / tasks.
- [x] 11.2 Run the smoke test matrix from design.md "Migration Plan" item 6 on a clean iPhone simulator.
- [x] 11.3 Confirm `make test` passes and there are no new linter warnings introduced.
- [x] 11.4 Confirm no `Localizable.xcstrings` changes other than the three new `paused` keys (use `git diff` against `simple-recurring-budgets/Resources/Localizable.xcstrings`).
- [ ] 11.5 Open the PR; reviewer must confirm the doc edits in tasks 10.1–10.4 landed in the same PR before merge.
- [ ] 11.6 After merge, archive the change per the OpenSpec workflow (`openspec archive settings-screen`).
