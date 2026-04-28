## Why

The Settings screen UI is in place (`simple-recurring-budgets/Views/SettingsView.swift`) and its layout, copy, and interaction model have been workshopped and finalized. Two of its sections are already wired (Budgets default carry-over toggle, Calendar week-start picker with confirmation), but the rest is mocked or behaviorally incomplete: Currency Display is a UI-only `@State` stub that does not persist, does not sync, and does not affect any monetary rendering anywhere else in the app; the iCloud Sync Status row checks account status only once and does not reflect whether the live SwiftData container is actually CloudKit-backed (vs a local-only fallback at launch); and the supporting docs (`product-features-planning.md` F-2.05, `tech-design-doc.md` §4.5 KV-key table) still describe Settings as "blank to start." This change finishes the implementation behind the existing UI, captures the screen's now-finalized contract in `openspec/specs/`, and brings the docs into alignment so future work is anchored to a single source of truth.

## What Changes

- **Persist & sync the Currency Display preference** through the existing `AppSettings` / `NSUbiquitousKeyValueStore` pattern.
  - Promote `CurrencyDisplayPreference` out of `SettingsView`'s `fileprivate` scope into a shared canonical type (proposed home: `Formatting/CurrencyDisplayPreference.swift`); cases stay `symbol` / `code` / `codeAndSymbol` with `String` raw values.
  - Add `AppSettings.currencyDisplay: CurrencyDisplayPreference` (default `.symbol`), backed by KV key `"currencyDisplay"` (stored as the enum's `String` raw value), with the same external-change observation pattern as the existing `defaultCarryOverEnabled` and `weekStartDay` keys.
  - Bind the picker in `SettingsView` to `$settings.currencyDisplay` (replaces the `@State` stub); preserve the existing `"\(label) — \(example)"` row format and the existing localized strings unchanged.
- **Make Currency Display actually affect monetary rendering globally** (per Q1 = global).
  - Extend `Decimal.formatted(currencyCode:locale:)` in `Formatters.swift` with a `display: CurrencyDisplayPreference` parameter (default `.symbol` to keep existing call sites compiling and their behavior identical when not migrated).
  - Implement the three presentations against `Decimal.FormatStyle.Currency`:
    - `.symbol` → `.currency(code:).presentation(.narrow)` (current default behavior).
    - `.code` → `.currency(code:).presentation(.isoCode)`.
    - `.codeAndSymbol` → composed string in the canonical `<ISO code> <localized symbol form>` pattern (per Q1a), letting bidi handle RTL placement; the symbol-form portion uses the same path as `.symbol` for consistency.
  - Update `BudgetRowView`'s amount renders, `BudgetRowView.rowAccessibilityLabel`, and `CarryOverFormatter.display` to read `settings.currencyDisplay` and pass it through.
  - **Examples in the Settings picker are derived live from the user's locale**, not hard-coded. Each row's example is produced by passing a fixed sentinel `Decimal` (proposed: `Decimal(25)`) through the same `Decimal.formatted(currencyCode:display:locale:)` formula being built in this change, with `currencyCode = Locale.autoupdatingCurrent.currency?.identifier ?? "USD"` (mirroring F-3.04's locale → currency convention; `"USD"` fallback if the locale has no currency). This means the picker shows exactly what the user will see in their own currency for each preference, e.g., for a French (fr_FR) user: `"Symbole — 25,00 €" / "Code — EUR 25,00" / "Code + Symbole — EUR 25,00 €"`. **This supersedes the previous "frozen example strings" decision** (which kept the en_US literals `"$25" / "USD 25" / "USD $25"`); the user is intentionally lifting that part of the copy freeze for these specific preview values.
- **Make the iCloud Sync Status row honest about real sync availability** (per Q2 = tri-state).
  - Introduce a small `@Observable SyncStatus` value type/object capturing the **launch-time container backing** (CloudKit-backed, local-fallback success, or container-failure-fatal) — derived from the analytics events already emitted in `simple_recurring_budgetsApp.makeProductionModelContainer` — and inject it into the SwiftUI environment alongside `AppSettings` and `Router`.
  - Replace the existing `loadICloudStatus()` two-state model (`available` / `unavailable`) with a tri-state derivation: `available` when account = available **and** container = CloudKit-backed; `paused` (a.k.a. "Sync paused / local only") when container fell back to local even though account may be available; `unavailable` when account is not available. `checking` remains for the initial load.
  - Observe `CKAccountChangedNotification` (and `NSUbiquityIdentityDidChange`) while the screen is alive so the row reactively updates if the user signs in/out without dismissing the sheet.
  - Add a new "paused" row variant (icon + label + footer copy) — content TBD in design.md, but distinct from the existing `available` and `unavailable` variants. Existing `available` and `unavailable` copy strings (and their accessibility labels and the unavailable footer) are unchanged.
- **Replace `fileprivate enum ICloudSyncStatus`** with the broader `SyncStatus`-derived view-state so the row's three (now four, counting `checking`) cases are first-class.
- **Wire (verify) "Send Feedback", "Rate the App", and the Done toolbar button.** No code change expected to "Send Feedback" (`Link` → `mailto:`) or "Rate the App" (`requestReview()`); they are wired today. Document this as the screen's contract in the new spec so future regressions surface.
- **Privacy Policy URL stays `https://example.com/privacy`** behind the existing `// TODO` comment in `AppInfo.privacyPolicyURL`. Out of scope per user direction; the spec captures only that the link exists, not its destination.
- **Do not change any user-facing copy.** All `String(localized:…)` keys, default values, and translator comments stay exactly as they appear today, including the `"USD $25"` example string and the `"Sign in to iCloud in Settings…"` footer. Concerns flagged separately in chat for later decisions.
- **Doc updates** (per Q4 = extend F-2.05):
  - **`docs/product-features-planning.md` F-2.05** — replace "content blank to start" / "Entry point button is placed in canonical place" with concrete acceptance criteria covering the six finalized sections (Budgets default carry-over, Calendar week-start with confirmation, Display currency-display preference, iCloud Sync Status, Support, About) and the Done dismissal. Do not duplicate F-2.07 (carry-over default) or F-5.01 (week-start) wording — cross-reference them.
  - **`docs/tech-design-doc.md` §4.5** — add `"currencyDisplay"` (`String`, `AppSettings`, "Currency display format preference for monetary amounts") to the KV-key table.
  - **`docs/tech-design-doc.md` §2.1 / new §X** — document the `SyncStatus` environment value and the launch-time container-mode plumbing convention as a small architectural addition; bump version-history row.
- **No SwiftData schema changes. No CloudKit container changes. No migration.** `Budget`, `ExpenseItem`, `BudgetMigrationPlan`, and `SchemaV1` are untouched. CloudKit record types are unaffected.

## Capabilities

### New Capabilities

- `settings-screen`: Behavior contract for the Settings screen (`SettingsView`) — the six sections listed above, the Done dismissal, and the rules for how Settings reads from / writes to `AppSettings` and observes iCloud sync availability. This capability is intentionally scoped to the **screen-level** UX contract (what is shown, what action each control performs, what state each row reflects). The persistence and sync behavior of individual settings continues to live in `app-settings`.

### Modified Capabilities

- `app-settings`: Add a new `currencyDisplay` setting requirement — `AppSettings.currencyDisplay: CurrencyDisplayPreference`, default `.symbol`, persisted under KV key `"currencyDisplay"` as the enum's `String` raw value, with the same external-change-observation guarantees as the existing two settings. Adds the `CurrencyDisplayPreference` enum to the spec's contract (cases, raw values, default) so it is a first-class capability symbol like `Weekday`. No requirements removed; no breaking changes to existing requirements.

_(`data-models`, `budget-lifecycle`, `budget-math`, `budgets-screen`, and `schema-versioning` are unaffected. Currency Display does not change `Budget.currencyCode` or any model field; it changes only **how** existing `Decimal` amounts are rendered.)_

## Impact

- **Modified code:**
  - `simple-recurring-budgets/Settings/AppSettings.swift` — add `currencyDisplay` stored property + KV key constant + read helper + external-change branch.
  - `simple-recurring-budgets/Views/SettingsView.swift` — promote `CurrencyDisplayPreference` out of `fileprivate`; bind picker to `$settings.currencyDisplay`; replace `loadICloudStatus()` with the new `SyncStatus`-driven tri-state derivation; observe `CKAccountChanged` / `NSUbiquityIdentityDidChange`; render the new "paused" row variant. **No copy changes** to any localized string in this file.
  - `simple-recurring-budgets/Formatting/Formatters.swift` — extend `Decimal.formatted(currencyCode:locale:)` with `display: CurrencyDisplayPreference` (default `.symbol`); implement the three presentations.
  - `simple-recurring-budgets/Views/BudgetsView.swift` — `BudgetRowView` reads `settings.currencyDisplay` and threads it through every `Decimal.formatted(currencyCode:…)` call (visible amount, accessibility label).
  - `simple-recurring-budgets/Views/CarryOverChip.swift` (and `CarryOverFormatter.display` in `Formatters.swift`) — accept and pass through the preference so the chip respects the global setting.
  - `simple-recurring-budgets/App/simple_recurring_budgetsApp.swift` — record container-mode result into the new `SyncStatus`; inject `SyncStatus` into the environment.
- **New code:**
  - `simple-recurring-budgets/Formatting/CurrencyDisplayPreference.swift` — canonical home for the `CurrencyDisplayPreference` enum (cases, `Identifiable`, `CaseIterable`, `Codable`, `String` raw values, localized `label`, hard-coded `example` mock strings). Exact filename / module placement deferred to design.md.
  - `simple-recurring-budgets/Sync/SyncStatus.swift` (or equivalent location TBD in design.md) — small `@Observable` value carrying the launch-time container backing and account-status cache, plus the derivation rule for the row view-state.
- **New tests** (Swift Testing):
  - `AppSettingsTests` gains coverage for `currencyDisplay`: default value on fresh store; persisted-value read on init; setter persists to store; external-change notification updates the property; invalid raw value falls back to default.
  - `FormattersTests` (or equivalent) gains coverage for the three Currency Display presentations across at least USD, EUR, and JPY locales (Latin and CJK / glyph-only) and at least one RTL locale (e.g., Arabic) to assert bidi-friendly composition for `.codeAndSymbol`.
  - `SettingsViewTests` (or a new file) covers: Currency Display picker writes to `AppSettings`; week-start confirmation alert applies pending value only on confirm; iCloud row maps each `(accountStatus, containerBacking)` combination to the correct view-state; `CKAccountChanged` triggers re-evaluation. UI-detail behavior beyond unit coverage stays in previews / smoke testing per `docs/tech-design-doc.md` §5.3.
- **Localization / Accessibility:**
  - **No new user-facing strings** for any existing row (Q5 confirmed scope is complete; copy is final).
  - **One new string set** is required for the new "Sync paused / local only" row variant (label + accessibility label + section footer). Exact keys and English source strings are decided in design.md and added to `Localizable.xcstrings` with `comment:` translator notes per `docs/tech-design-doc.md` §5.1. **These strings are new product copy and the user will be asked to approve before implementation.** (Captured as a design.md decision and a tasks.md gate.)
- **Persistence / Sync:** Adds one new `NSUbiquitousKeyValueStore` key (`"currencyDisplay"`); no SwiftData schema changes. Within the 1 MB / 1024-key NSUKVS budget by a wide margin (`docs/tech-design-doc.md` §4.5).
- **Entitlements / capabilities:** None added. Uses existing iCloud + CloudKit entitlements.
- **No new third-party dependencies.**

## Doc alignment

- **Aligned with `docs/main-prd.md`** — no global constraints touched. PRD §6.7 (Over/Under) is unaffected. PRD §6.5 (currency: per-Budget, no exchange conversions) is preserved — Currency Display changes **how** an amount with an existing per-Budget currency code is rendered; it does not introduce a global currency override or any conversion.
- **Aligned with `docs/ux-design-brief.md`** — UX brief lists "Settings: Start of week, currency display, skin selection, About. Minimal." This change implements three of those four (start of week is already shipped via F-5.01); skin selection stays out of scope (T-4 / F-4.01–02). Tone (calm / understated) is preserved by leaving the workshopped copy unchanged.
- **Conflict with `docs/product-features-planning.md` F-2.05** — F-2.05 currently reads "Settings screen; content blank to start. Acceptance Criteria: Entry point button is placed in canonical place." The screen has materially expanded. **Resolution: update F-2.05** to enumerate the now-finalized sections (cross-referencing F-2.07 and F-5.01 rather than restating their requirements). Keeping a single F-ID anchored to the screen avoids fragmenting the screen's contract across multiple feature IDs.
- **Conflict with `docs/tech-design-doc.md` §4.5** — KV-key table currently lists only `"defaultCarryOverEnabled"` and `"weekStartDay"`. **Resolution: add `"currencyDisplay"`** with type, owner, and purpose.
- **Tech-design-doc architectural addition** — the launch-time `SyncStatus` plumbing (container-mode → environment value) is a new pattern that warrants a short note. Decision deferred to design.md whether this lives in a new sub-section or as an addition to §4.5; a version-history row will be added.
- **No conflict with `docs/main-prd.md`** — Settings screen UX details are below the PRD's altitude.
- **Doc updates required after implementation** (covered as explicit tasks in tasks.md so they don't drift):
  - `docs/product-features-planning.md` (F-2.05 — extended acceptance criteria; cross-references to F-2.07 and F-5.01 stay accurate).
  - `docs/tech-design-doc.md` (§4.5 KV-key table; new architectural note for `SyncStatus`; version-history row).
  - `docs/main-prd.md` — none.
