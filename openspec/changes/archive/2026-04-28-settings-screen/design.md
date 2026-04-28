## Context

The Settings screen UI lives in `simple-recurring-budgets/Views/SettingsView.swift` and was workshopped to its current shape with finalized layout, copy, and interaction model. Only two of its six sections are wired today:

- **Budgets → Carry-Over toggle** is wired via `$settings.defaultCarryOverEnabled` (synced via `NSUbiquitousKeyValueStore`, see `openspec/specs/app-settings/spec.md`).
- **Calendar → Week Starts On** is wired via `settings.weekStartDay` plus a `pendingWeekStart`-gated confirmation alert before commit. Downstream behaviour is automatic: `BudgetLifecycleService.refreshAndSave` reads `settings.weekStartDay` at access time, so weekly and biweekly budgets reflect the change on next view appearance / `scenePhase == .active`.

Four sections are mocked or partial:

- **Display → Currency Display** uses a `fileprivate enum CurrencyDisplayPreference { symbol, code, codeAndSymbol }` and a `@State` stub. The picker doesn't write anywhere, isn't synced, doesn't survive relaunch, and doesn't affect any monetary rendering elsewhere in the app. The in-line comment says it "will become a stored AppSettings property with a matching NSUbiquitousKeyValueStore key before launch — follow the existing AppSettings pattern."
- **iCloud → Sync Status** calls `CKContainer.default().accountStatus()` once on `.task` and renders a two-state row (`available` / `unavailable`) plus a transient `checking`. It does not observe iCloud account changes while the screen is open, and "Syncing via iCloud" can be wrong: at launch, `simple_recurring_budgetsApp.makeProductionModelContainer` falls back to a local-only `ModelConfiguration(cloudKitDatabase: .none)` if the CloudKit container fails to construct, but the row will still say "Syncing via iCloud" if the user is signed in.
- **Support** — `Send Feedback` (`Link` → `mailto:`) and `Rate the App` (`requestReview()`) are wired correctly; `Privacy Policy` points to `https://example.com/privacy` (intentional `// TODO`, out of scope per user direction).
- **About** — version + build display is wired correctly.

The `Done` toolbar item dismisses the sheet correctly (`@Environment(\.dismiss)`).

`SettingsView` is reached from `RootView` via `router.sheet = .settings` (entry point in `BudgetsView.toolbar`). It is presented as a sheet with a `NavigationStack` inside.

Constraints in play:

- `docs/tech-design-doc.md` §2.1 ("View + Services, ViewModels on demand") — none of the four escalation triggers apply for the Settings screen even after this change: there is no draft state (writes commit on change with one specific exception below), no async work beyond a single `accountStatus()` call and a notification observer, no multi-step chaining, no expensive derived display state. Settings stays a plain SwiftUI view.
- `docs/tech-design-doc.md` §4.5 ("App Settings (NSUbiquitousKeyValueStore)") — preferences live in `NSUbiquitousKeyValueStore` via the `AppSettings` `@Observable` class with external-change observation; new keys go in the §4.5 KV-key table.
- `docs/tech-design-doc.md` §5.1 — every new user-facing string lives in `Localizable.xcstrings` with `comment:` for translators.
- `docs/tech-design-doc.md` §4.4 — CloudKit is last-writer-wins; this is acceptable for a string-valued preference.
- `docs/main-prd.md` §6.5 — currency is **per-Budget** with no exchange conversion; this change only affects **how** an amount in an existing currency is rendered.
- `docs/main-prd.md` §6.7 — Over/Under behavior is unchanged.
- `docs/ux-design-brief.md` — calm / understated / no exclamation marks; preserved by leaving copy unchanged.

## Goals / Non-Goals

**Goals:**

- Persist & sync **Currency Display** as a first-class `AppSettings` property and propagate it through every monetary render (per Q1 = global; per Q1a = `<ISO code> <localized symbol form>`).
- Reflect actual sync availability on the **iCloud** row using a tri-state model (per Q2 = available / paused / unavailable) that combines (a) CloudKit account status and (b) launch-time container backing, with reactive updates while the sheet is open.
- Codify the Settings screen's now-finalized contract in a new `openspec/specs/settings-screen/spec.md` so the screen's behavior is anchored in OpenSpec the way `budgets-screen` is for the list.
- Extend the existing `app-settings` spec with the new `currencyDisplay` requirement so `AppSettings` is the single home for KV-store-backed preferences.
- Update `docs/product-features-planning.md` (F-2.05) and `docs/tech-design-doc.md` (§4.5 KV-key table; new architectural note for the `SyncStatus` plumbing).
- Keep `SettingsView` a plain SwiftUI view — no `BudgetsViewModel`-style escalation.
- Preserve **all** existing user-facing copy verbatim; only the new "Sync paused" row variant introduces new strings, and those are gated on user approval before implementation.

**Non-Goals:**

- Replacing the `Privacy Policy` URL (intentional `// TODO`).
- Replacing the `Send Feedback` `mailto:` `Link` with `MFMailComposeViewController` (per Q3 = leave as `Link`).
- Adding new sections (skin selection, debug, account / data export, "Reset all settings"). Per Q5, the six existing sections are the full scope.
- ~~Locale-aware Currency Display picker examples~~ — lifted per Decision 1 revision note; live locale-aware previews are now the implemented and specified behavior.
- Building a full live "sync activity" indicator (progress, last-synced timestamp). SwiftData + CloudKit does not expose a clean public API for this, and the row's purpose is **availability**, not throughput.
- Changing any `Budget` or `ExpenseItem` model field, schema, or migration plan.
- Modifying `BudgetLifecycleService`, `BudgetCalculator`, or `PeriodCalculator`. Currency Display is purely a render-time concern.

## Decisions

### Decision 1: `CurrencyDisplayPreference` placement and identity

**Choice:** Extract `CurrencyDisplayPreference` from `SettingsView.swift`'s `fileprivate` scope into a new file `simple-recurring-budgets/Formatting/CurrencyDisplayPreference.swift`. The enum becomes `internal`, with these properties:

- `String`-backed raw values for KV-store stability: `"symbol"`, `"code"`, `"codeAndSymbol"`. (`Int` raw values are rejected — string raw values survive enum-case reordering and are self-describing in the KV store, matching the cross-app convention `Weekday` chose for `Int` only because it had to align with `Calendar.firstWeekday`.)
- `CaseIterable`, `Identifiable (id: Self)`, `Codable`, `Sendable`.
- Existing `label: String` (already localized via `String(localized: …, comment: …)`).
- **`func example(locale: Locale = .autoupdatingCurrent) -> String`** — produces a live preview of how a sample amount renders under this preference in the user's own locale. Implementation:
  ```swift
  func example(locale: Locale = .autoupdatingCurrent) -> String {
      let code = locale.currency?.identifier ?? "USD"
      return Decimal(25).formatted(currencyCode: code, display: self, locale: locale)
  }
  ```
  The `"USD"` fallback mirrors `docs/product-features-planning.md` F-3.04 ("Defaults to locale's currency; USD if unable to determine at all"). This routes the picker preview through the same `Decimal.formatted(currencyCode:display:locale:)` formula used by `BudgetRowView` and `CarryOverChip`, so the picker always shows what the user will actually see for each preference — for example: en_US → `"$25.00" / "USD 25.00" / "USD $25.00"`; fr_FR → `"25,00 €" / "EUR 25,00" / "EUR 25,00 €"`; ja_JP → `"￥25" / "JPY 25" / "JPY ￥25"`. The `Locale` parameter is defaulted for production callers (`autoupdatingCurrent` so the picker re-renders if the user's device locale changes) and explicit for deterministic tests.

> **Revision note:** an earlier draft of this decision (and the corresponding earlier draft of `specs/app-settings/spec.md` and `specs/settings-screen/spec.md`) kept `example` as hard-coded mock strings (`"$25" / "USD 25" / "USD $25"`) on the rationale that side-by-side contrast would teach the user the difference between the three preferences. The user intentionally lifted that constraint after weighing the trade-off: locale-honest previews outweigh the lost en_US-specific contrast, and locales where the symbol and code render identically (e.g., `de_CH` / CHF) accurately telegraph that the preference is effectively a no-op for that user — which is itself information. This decision now governs.

The previously-`fileprivate` definition in `SettingsView.swift` is deleted.

**Alternatives considered:**

- **`Domain/CurrencyDisplayPreference.swift`** — rejected: `Domain/` is reserved for SwiftData-free business services (`PeriodCalculator`, `BudgetCalculator`, `BudgetLifecycleService`) per `docs/tech-design-doc.md` §5.4. A render-format enum doesn't belong there.
- **Co-locate inside `Formatters.swift`** — rejected: `Formatters.swift` is already growing (Money / CarryOver / Date sections); a separate file keeps the responsibility lines tidy.
- **`Settings/CurrencyDisplayPreference.swift`** — viable; rejected only because the `Settings/` folder currently holds the persistence layer (`AppSettings.swift`, `KeyValueStore.swift`) and the enum's primary use is in formatting, not persistence. Reasonable to flip if reviewers prefer.

**Rationale:** Keeping the enum next to `Formatters.swift` co-locates the format preference with the formatter that consumes it. The `internal` access level is sufficient — no test target reaches in.

### Decision 2: Currency rendering formula for the three preferences

**Choice:** Extend `Decimal.formatted(currencyCode:locale:)` in `Formatters.swift` with a `display: CurrencyDisplayPreference = .symbol` parameter. Implementation:

```swift
extension Decimal {
    func formatted(
        currencyCode: String,
        display: CurrencyDisplayPreference = .symbol,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch display {
        case .symbol:
            return self.formatted(.currency(code: currencyCode).locale(locale))
        case .code:
            return self.formatted(
                .currency(code: currencyCode).presentation(.isoCode).locale(locale)
            )
        case .codeAndSymbol:
            let symbolForm = self.formatted(.currency(code: currencyCode).locale(locale))
            return "\(currencyCode) \(symbolForm)"
        }
    }
}
```

Behavior notes:

- The default value `.symbol` keeps every existing call site (`BudgetRowView`, `CarryOverFormatter`, etc.) compiling without changes and behaviorally identical until each call site is migrated to thread the preference through.
- `.symbol` uses the **default presentation** (no explicit `.narrow` / `.standard`) so each locale's most-conventional symbol form is used (e.g., `"$25"` in en_US, `"25 €"` in fr_FR). An earlier draft said `.narrow` — corrected here to avoid regressing locales whose narrow form drops disambiguating context (e.g., `CA$ 25` → `$25` in en_CA). The English-locale visual on the Settings picker example matches this default for USD.
- `.code` uses `.presentation(.isoCode)` — Apple's documented presentation for "show the ISO code in place of the symbol."
- `.codeAndSymbol` composes `<code> <symbolForm>` per Q1a. The space between the two parts is a regular ASCII space; bidirectional text rendering on iOS handles RTL placement automatically when the surrounding context is RTL. We do not insert explicit `\u{200E}` / `\u{200F}` markers — Apple's default text rendering chooses correctly when each token has a strong directional class. Tests will assert the produced string and visual rendering on at least one RTL locale (Arabic).
- Implementation uses **two FormatStyle calls** for `.codeAndSymbol` (one for the code presentation we discard, one for the symbol form we keep) — actually one: the code-form string isn't needed since we use the raw `currencyCode` parameter directly, which is the canonical ISO 4217 code already. This avoids a second FormatStyle round-trip.

**Alternatives considered:**

- **`Decimal.FormatStyle.Currency.presentation(.standard)`** for `.codeAndSymbol` — rejected: `.standard` typically renders one form (code OR symbol depending on locale). It is not "code + symbol" together.
- **Extracting the symbol via `Locale.localizedString(forCurrencyCode:)` + `NumberFormatter`** — rejected: bypasses Foundation's modern format styles, gets symbol-extraction wrong for several locales, and re-implements behavior already correct in `.currency(code:)`.
- **Concatenating with a non-breaking space (`\u{00A0}`)** — under consideration; default to ASCII space for now to keep test assertions deterministic and copy obvious in the catalog. If reviewers prefer NBSP for visual cohesion, change is a one-character edit.
- **A new `Decimal.formatted(currencyCode:display:)` overload that takes settings** rather than a default-valued parameter — rejected: adds a second public API surface for the same behavior. A defaulted parameter is the simplest backwards-compatible extension.

**Rationale:** The defaulted parameter lets us roll out call-site migrations incrementally; the formula is a thin layer over Foundation's first-party `Decimal.FormatStyle.Currency`; the `.codeAndSymbol` composition uses the same symbol path as `.symbol` so the two stay visually consistent.

### Decision 3: Where the preference is read at the call site

**Choice:** Each render site that needs the preference reads `@Environment(AppSettings.self).currencyDisplay` at render time and threads it through `Decimal.formatted(...)`. Specifically:

- `BudgetRowView` already has `@Environment(AppSettings.self) private var settings`; pass `display: settings.currencyDisplay` into both the visible `remaining.formatted(currencyCode:)` and the accessibility-label calls.
- `CarryOverChip` does **not** today take `AppSettings`. We extend `CarryOverChip` and `CarryOverFormatter.display(_:currencyCode:locale:)` with a `display: CurrencyDisplayPreference = .symbol` parameter; `BudgetRowView` (which owns the chip) passes `settings.currencyDisplay` down. The chip itself does **not** read the environment directly — that keeps it deterministic in previews and tests.
- Future render sites (`BudgetView`, expense rows, Add/Edit Budget) will follow the same convention when they ship.

**Alternatives considered:**

- **`@Environment` lookup inside `CarryOverChip`** — rejected: makes the chip implicitly depend on a global context (harder to preview / test) and surprising for a leaf view.
- **Pre-format strings in a higher layer** — rejected: monetary values are typed (`Decimal`) until render; pre-formatting strings forces every consumer to lose precision and locale-awareness.
- **Read from a `@Query` of `AppSettings`** — N/A: `AppSettings` is `@Observable`, not `@Model`. The environment value is the canonical access path.

**Rationale:** Threading the preference explicitly through render functions and through the leaf chip keeps the data flow visible and keeps leaf views pure. `AppSettings` is observed once at the `BudgetRowView` boundary; SwiftUI re-renders cleanly when the preference changes.

### Decision 4: `AppSettings.currencyDisplay` shape and KV-store contract

**Choice:** Add to `AppSettings`:

- `static let currencyDisplayKey = "currencyDisplay"` next to the existing key constants.
- `var currencyDisplay: CurrencyDisplayPreference { didSet { … } }` mirroring the `defaultCarryOverEnabled` / `weekStartDay` pattern: skip writes when `isApplyingFromStore`, otherwise `store.set(currencyDisplay.rawValue, forKey: currencyDisplayKey); _ = store.synchronize()`.
- New `KeyValueStore.set(_ value: String, forKey:)` overload added to the protocol and implemented by both `NSUbiquitousKeyValueStore` (already supports `String` via inherited API) and `MockKeyValueStore`.
- Initial value derivation in `init`: `Self.readCurrencyDisplay(from: store)`. The static reader returns `.symbol` for missing values, parses `String` raw values into the enum, and falls back to `.symbol` for unrecognized strings (forward-compat: a future case introduced on a newer device that syncs back to an older device will not crash; the older device shows `.symbol` until it updates).
- External-change observer extension: `applyKeys` adds a branch for `currencyDisplayKey` that re-reads the value and assigns it inside the `isApplyingFromStore` window so the assignment doesn't loop back to the store.
- `reloadAllFromStore` extends its key set to include `currencyDisplayKey`.

**Alternatives considered:**

- **`Int` raw value storage** — rejected: would require renumbering protections and an explicit `Int → enum` mapping; string raw values are clearer in the KV store and self-documenting. KV-store cost difference is negligible (3–14 bytes vs 8 bytes).
- **A separate `CurrencyDisplaySettings` `@Observable`** — rejected: a single small enum doesn't deserve its own class. `AppSettings` is the canonical home and already uses the same pattern for two other settings.
- **Skip external-change observation for this key** — rejected: it would silently make this preference inconsistent across devices, contradicting the spec's "external-change observation" requirement and the §4.5 doc rule.

**Rationale:** Mirrors the established `AppSettings` pattern exactly; no new abstractions; backwards-compatible when an older app version reads a value it doesn't recognize.

### Decision 5: `SyncStatus` plumbing — a small `@Observable` injected into the environment

**Choice:** Introduce a new file `simple-recurring-budgets/Sync/SyncStatus.swift` (folder is new; one-file directory is fine) containing:

```swift
@Observable
final class SyncStatus {
    /// The persistence backing the launched ModelContainer chose at app start.
    /// Set once during app init; never mutated thereafter.
    enum ContainerBacking: Sendable { case cloudKit, localFallback }

    let containerBacking: ContainerBacking

    /// Last-known account status. Initialized to .checking; updated by SettingsView's
    /// task and by NSNotificationCenter observers of CKAccountChanged /
    /// NSUbiquityIdentityDidChange. Other parts of the app may also read it.
    enum AccountStatus: Sendable { case checking, available, unavailable }
    var accountStatus: AccountStatus = .checking

    init(containerBacking: ContainerBacking)
}
```

Plus a derivation extension consumed by the row:

```swift
extension SyncStatus {
    enum RowState: Sendable { case checking, available, paused, unavailable }
    var rowState: RowState {
        switch (containerBacking, accountStatus) {
        case (_, .checking):                          return .checking
        case (.cloudKit, .available):                 return .available
        case (.cloudKit, .unavailable):               return .unavailable
        case (.localFallback, .available):            return .paused
        case (.localFallback, .unavailable):          return .unavailable
        }
    }
}
```

Wiring:

- `simple_recurring_budgetsApp.makeProductionModelContainer` returns a tuple `(ModelContainer, SyncStatus.ContainerBacking)` — `.cloudKit` for the CloudKit-backed path, `.localFallback` for the on-disk-only fallback path. The fatal-failure path keeps `fatalError` semantics; no `SyncStatus` is observable in that case because the app does not launch.
- The app's `init` constructs a `SyncStatus(containerBacking: …)` from that result and stores it in `@State`.
- `WindowGroup` injects it via `.environment(syncStatus)`.
- `SettingsView` adds `@Environment(SyncStatus.self) private var syncStatus` and replaces `loadICloudStatus()`'s state with `syncStatus.accountStatus = …` writes, plus reads `syncStatus.rowState` in the iCloud row.
- The `.task` block in `SettingsView` keeps doing the initial `CKContainer.default().accountStatus()` call but assigns into `syncStatus.accountStatus` instead of the local `@State`.
- Two `NotificationCenter` observers are added (within a `.task` that suspends until cancelled, or as `Task` lifecycles tied to the view): one for `NSNotification.Name.CKAccountChanged`, one for `NSUbiquityIdentityDidChange`. Each re-runs the `accountStatus()` query and writes the result into `syncStatus.accountStatus`. Observers are removed on view disappearance.

**Alternatives considered:**

- **A free-floating module-level singleton** — rejected: harder to reason about in tests and previews; the environment mechanism is the established pattern (`AppSettings`, `Router`, `analytics`).
- **Extending `AppSettings` with the iCloud status fields** — rejected: `AppSettings` is the KV-store persistence boundary; sync availability is ephemeral, not a stored preference. Conflating them would muddle that boundary.
- **A boolean `isCloudKitBacked` instead of an enum** — rejected: Swift switch-exhaustiveness on the enum future-proofs the row when other backings appear (e.g., a future "in-memory debug" backing exposed in DEBUG previews).
- **Recompute `containerBacking` dynamically at every read** — rejected: the SwiftData container is decided once at launch and the SwiftData/CloudKit framework does not expose a "currently using CloudKit?" runtime probe. Capturing the launch-time decision is the only honest answer.

**Rationale:** The container-backing decision is already made and emitted as analytics events; capturing it for UI consumption is essentially free. Tri-state matches the user choice (Q2 = C). Observing notifications keeps the row honest while the sheet is open without polling.

### Decision 6: New "Sync paused / local only" row variant (copy gate)

**Choice:** The `paused` view-state renders a row distinct from `available` and `unavailable`. Three new `String(localized: …)` keys are introduced:

- `settings.iCloud.paused` — main row label (English source proposal: `"iCloud Sync Paused"` — pending user approval).
- `settings.iCloud.paused.accessibilityLabel` — VoiceOver label (English source proposal: `"iCloud sync is paused. Your budgets are saved on this device but not syncing to other devices."` — pending user approval).
- `settings.iCloud.paused.footer` — section footer copy when `rowState == .paused` (English source proposal: `"Your budgets are saved on this device only. Restart the app to retry iCloud sync."` — pending user approval).

The row uses an SF Symbol distinct from the existing ones; proposed: `exclamationmark.icloud` rendered in `.orange` (mirrors the existing `unavailable` color choice; the brief calls for restraint, no alarm reds). No exclamation marks in the copy itself per the UX brief.

**Crucially: these are new product copy strings, and the user has stated all displayed copy is finalized and must not change without approval.** Implementation is gated on the user approving the proposed strings (or supplying alternates) before tasks.md item 12 begins. This is captured both here and in `tasks.md` as an explicit pre-implementation gate.

**Alternatives considered:**

- **Reuse existing `settings.iCloud.unavailable` copy for the `paused` state** — rejected: misleading. "iCloud Not Available" is true for "user not signed in"; for a signed-in user with a local-fallback container, the cause is different (the app's container failed to wire up CloudKit at launch, not iCloud unavailability).
- **Don't show a distinct state at all (collapse `paused` into `unavailable`)** — rejected: that's the status quo bug this change is fixing. The UI would still claim "iCloud Not Available" when iCloud itself is fine, only the app's binding is broken.
- **Show a "Retry" button in the paused row** — rejected for v1: the only honest retry is "relaunch the app" because `ModelContainer` is built once at launch; in-app retry would require tearing down and rebuilding the entire SwiftData stack, which is high-risk for a small UX gain. Surfaced as an Open Question for follow-up.

**Rationale:** The tri-state choice is honest and bounded. Distinct copy is the only way to communicate the distinct cause to the user.

### Decision 7: No `BudgetsViewModel`-style escalation; `SettingsView` stays a plain SwiftUI view

**Choice:** No new `@Observable` Settings-screen view model. The screen continues to read `AppSettings` directly and own only the same kinds of transient `@State` it has today (`pendingWeekStart`).

**Alternatives considered:**

- **`SettingsViewModel`** to wrap the four sections — rejected against `docs/tech-design-doc.md` §2.1: no async work beyond a single `accountStatus()` call (plus notification observers, which a VM would not simplify), no draft state beyond `pendingWeekStart` (a 1-field draft well below the §2.1 grey-area threshold), no multi-step chaining, no expensive derived state. The escalation criteria are not met.

**Rationale:** The §2.1 contract: VMs are added when triggers fire, not speculatively.

### Decision 8: Tech-design-doc edit scope

**Choice:** Update `docs/tech-design-doc.md` in this change:

- **§4.5 KV-key table** — add a row for `"currencyDisplay"` (`String`, `AppSettings`, "Currency display format preference for monetary amounts").
- **New paragraph in §4 (or end of §4.5)** — short note that documents the `SyncStatus` environment value: where it comes from (launch-time container construction outcome), what it carries (`containerBacking`, `accountStatus`), and that screens consume it via `@Environment(SyncStatus.self)`. One paragraph; no new sub-section.
- **Version-history row** — bump (e.g., 0.9 → 1.0 or 0.9, depending on current pre-edit value) with the changes summary.

**Alternatives considered:**

- **Skip the `SyncStatus` doc note** — rejected: `Router` and `AppSettings` are documented in §2 / §4.5 respectively; introducing a third environment-injected `@Observable` with no doc trace would invite future drift.
- **Add a full sub-section on `SyncStatus`** — overkill; the type is small and the docs already establish the pattern. A paragraph is enough.

**Rationale:** Minimal, durable, anchored in existing docs structure.

### Decision 9: F-2.05 doc edit shape

**Choice:** Rewrite F-2.05's Acceptance Criteria as a list of the now-finalized sections (Budgets default carry-over → cross-reference to F-2.07; Calendar week-start with confirmation alert → cross-reference to F-5.01; Display currency-display preference; iCloud Sync Status (tri-state); Support: Send Feedback / Rate the App / Privacy Policy; About: version + build; Done dismissal). Description prose updates to reflect that the screen is no longer "blank to start."

The `docs/product-features-planning.md` Status field for F-2.05 stays "Open" until this change archives; archive moves it to "Closed" if the existing convention has been established (TBD on review of prior archives). Follow whatever the prior archive cycles did.

**Rationale:** Single anchor for the screen's contract; cross-references avoid redundancy with F-2.07 / F-5.01.

### Decision 10: Test layout

**Choice:**

- `simple-recurring-budgetsTests/Settings/AppSettingsTests.swift` (or wherever the existing `AppSettings` tests live — TBD on inspection during apply): add the `currencyDisplay`-related scenarios listed in proposal.md.
- `simple-recurring-budgetsTests/Formatting/FormattersTests.swift`: cover the three Currency Display presentations across at least USD, EUR, JPY (CJK-specific symbol form), and one RTL locale (Arabic, e.g., `Locale(identifier: "ar_SA")`). Assertions use deterministic `Locale` and `Calendar` injection per `docs/tech-design-doc.md` §5.4 conventions.
- `simple-recurring-budgetsTests/Views/SettingsViewTests.swift` (new): cover (a) Currency Display picker writes `AppSettings.currencyDisplay`; (b) week-start confirmation alert applies pending value only on confirm and discards on cancel; (c) `SyncStatus.rowState` mapping table is exhaustive and correct for all `(containerBacking, accountStatus)` combinations; (d) `CKAccountChanged` (or its mock equivalent) triggers `SyncStatus.accountStatus` re-evaluation. Where appropriate, exercise the view-state derivation in a pure unit test against `SyncStatus` without instantiating SwiftUI views.

**Alternatives considered:**

- **No `SettingsViewTests.swift`; rely on previews + smoke testing** — rejected: the iCloud tri-state mapping is logic that deserves a unit test, and the picker → AppSettings binding is easy to assert.

**Rationale:** Tests track the new behavior at the granularity of the spec requirements; the pure derivation is fully testable without SwiftUI.

## Risks / Trade-offs

- **[Currency Display preference change feels delayed in already-rendered rows]** → SwiftUI re-evaluation is automatic for `@Observable`-tracked properties, so `BudgetRowView` rerenders when `settings.currencyDisplay` changes. The row's `BudgetLifecycleResult` does **not** need to refresh — Currency Display is purely a render-time concern, no math changes. **Mitigation:** verify in preview / smoke testing; no code mitigation needed.
- **[Older app version on a paired device sees an unrecognized `currencyDisplay` raw value]** → Unrecognized string falls back to `.symbol` per `readCurrencyDisplay`. The newer device's choice is preserved in the KV store and re-applied if the older device updates later. **Mitigation:** documented; `.symbol` is the safest default (current de-facto behavior).
- **[`CKAccountChanged` notification fires on background queue]** → Main-actor isolation is maintained because `SettingsView` uses two concurrent `for await _ in notifications { … }` loops inside a `withTaskGroup`, both of which run in tasks spawned from the `.task` modifier — which is `@MainActor`-isolated. Child tasks inherit that isolation, so all writes to `syncStatus.accountStatus` happen on the main actor without an explicit `MainActor.assumeIsolated` hop. **Mitigation:** intrinsic in the `withTaskGroup` + `.task` design; no explicit actor hop needed.
- **[`SyncStatus` is observed but its `containerBacking` is set once and never changes]** → Marking `containerBacking` as `let` makes this safe: SwiftUI tracks `accountStatus` and the derived `rowState`. **Mitigation:** intrinsic in the type design.
- **[Bidi composition for `.codeAndSymbol` looks wrong in some RTL contexts]** → Apple's text rendering handles bidi at draw time using the strong directional class of each token; ASCII space + RTL surrounding context produces correct visual order in every test locale tried in similar Apple sample code. **Mitigation:** add an Arabic-locale unit test asserting the produced `String` and a manual visual check on an Arabic preview.
- **[Compatibility with future per-Budget currency-display override]** → If a future feature adds a per-Budget override, the call-site convention "preference is the last-resolved value passed in" still holds; the formatter doesn't care where the preference came from. **Mitigation:** intrinsic; no premature accommodation needed now.
- **[New "Sync paused" copy not approved before implementation]** → Implementation is blocked on copy approval; tasks.md sequences the copy gate before the implementation tasks for that row. **Mitigation:** explicit gate; no ambiguity.

## Migration Plan

1. **Single PR landing this change.** All code, spec, doc, and test changes ride together so `BudgetRowView`, `CarryOverChip`, `CarryOverFormatter`, the formatter extension, `AppSettings`, `SettingsView`, `SyncStatus`, the app entry point, and the tests update in one consistent step.
2. **No data migration.** No SwiftData schema changes. The new `"currencyDisplay"` KV key is a new key with a documented default — fresh installs read `.symbol`; users without an existing iCloud-paired value on first run see `.symbol`. Existing installs are not affected by any other key.
3. **Localization catalog updates** — only the three new "paused" row strings are added (gated on user approval). All existing strings are untouched.
4. **Doc updates land in the same PR** — `docs/product-features-planning.md` (F-2.05) and `docs/tech-design-doc.md` (§4.5 KV-key table + new `SyncStatus` paragraph + version-history row).
5. **Rollback strategy.** Revert the single PR. The new `"currencyDisplay"` KV key remains in iCloud KV store but is harmless (no consumer); a follow-up reset-key task could remove it but isn't required. `Budget` and `ExpenseItem` data is unchanged.
6. **Smoke test matrix on a clean iPhone simulator (per `docs/tech-design-doc.md` §5.3):**
   - Currency Display: switch through all three options on the picker; confirm `BudgetRowView` amounts and the carry-over chip update in place.
   - Week-start: change the picker to a different day; confirm alert appears; tap Cancel — no change; tap again, tap Change — value persists; weekly / biweekly budgets refresh on next view appearance.
   - iCloud row: simulator without an iCloud account → `unavailable`; sign in → row updates while sheet is open (`available`); use the DEBUG `appDatabaseLaunchMode = .emptyInMemory` (or similar fallback path) to verify the `paused` row renders when the container is local-only despite being signed in. (`appDatabaseLaunchMode` is DEBUG-gated.)
   - Send Feedback opens the system mail composer with the prefilled subject; Rate the App opens the StoreKit prompt; Privacy Policy opens `https://example.com/privacy` in the browser (TODO acknowledged); Done dismisses the sheet.
   - VoiceOver: each row reads its label and hint correctly; the `paused` row reads its accessibility label fully (regression check).
   - `make test` (or `bash scripts/test.sh`) passes per `.cursor/rules/ios-build-test.mdc`.

## Open Questions

- **(Approval needed)** The three new "paused" row English source strings (label, accessibility label, footer copy) — exact wording TBD. Listed in Decision 6 as a placeholder. Implementation gates on this.
- **In-app "Retry sync" affordance for the `paused` state** — deliberately deferred. No code in this change. If post-launch telemetry or feedback shows the `paused` state happens often enough to need a retry beyond "relaunch the app," a follow-up change can teardown / rebuild the SwiftData stack at runtime; this is non-trivial and outside scope.
- **Privacy Policy real URL** — explicit user-flagged TODO; not part of this change.
