# Settings screen

Screen-level UX contract for `SettingsView` — sections present, controls in each section, the Done dismissal, the iCloud sync-status derivation, and the rules for how Settings reads from and writes to `AppSettings`. The persistence and sync behavior of individual settings (`defaultCarryOverEnabled`, `weekStartDay`, `currencyDisplay`) lives in the `app-settings` capability and is referenced from here, not duplicated. Synced from change `settings-screen` (2026-04-28).

## Requirements

### Requirement: Settings entry point and presentation

The app SHALL present `SettingsView` as a sheet over the navigation host (`RootView`) when `Router.sheet == .settings`. The user SHALL reach this state from a toolbar entry on the Budgets screen (`BudgetsView` toolbar gearshape button), per the established `Router` pattern.

`SettingsView` SHALL host its content inside a `NavigationStack` with a navigation title (localized) and an inline title display mode. The screen SHALL apply the app's global background via the `.appBackground()` modifier.

The screen SHALL provide a confirmation-action toolbar item titled "Done" (localized) that dismisses the sheet via `@Environment(\.dismiss)`.

#### Scenario: Opening Settings from the Budgets screen

- **WHEN** the user taps the gearshape (Settings) toolbar button on the Budgets screen
- **THEN** the system SHALL set `Router.sheet = .settings` and present `SettingsView` as a sheet.

#### Scenario: Dismissing Settings via Done

- **WHEN** the user taps the "Done" toolbar button on `SettingsView`
- **THEN** the sheet SHALL dismiss and `Router.sheet` SHALL return to `nil`.

---

### Requirement: Budgets section — default carry-over toggle

The Settings screen SHALL include a "Budgets" section that contains a toggle bound to `AppSettings.defaultCarryOverEnabled`. The toggle's persistence, default value, and external-change handling are governed by the `app-settings` capability — this requirement governs only the screen's binding and presentation.

The section SHALL include a localized footer explaining that the toggle controls the default for new budgets only and that existing budgets are unaffected. The toggle SHALL be tinted with `Color.accentColor` so the picker color follows the app's tint.

#### Scenario: Toggling the default carry-over

- **WHEN** the user toggles the Budgets section's default-carry-over switch
- **THEN** the system SHALL set `AppSettings.defaultCarryOverEnabled` to the toggle's new value, which (per the `app-settings` capability) persists to `NSUbiquitousKeyValueStore` and syncs across the user's iCloud-paired devices.

#### Scenario: External change reflected in the toggle

- **WHEN** another iCloud-paired device writes a new value for the default-carry-over preference and the change propagates to this device while `SettingsView` is open
- **THEN** the toggle SHALL update to the new value (driven by `AppSettings`'s `@Observable` change emission and external-change observer).

---

### Requirement: Calendar section — week-start picker with confirmation

The Settings screen SHALL include a "Calendar" section that contains a menu-style `Picker` bound (with confirmation gating) to `AppSettings.weekStartDay`. The picker SHALL list every `Weekday` case (Sunday through Saturday) using locale-aware standalone weekday names from `Calendar.current.standaloneWeekdaySymbols`.

Selecting a different value from the current `AppSettings.weekStartDay` SHALL NOT directly write the value. Instead the system SHALL hold the candidate value in a transient view-local state and present a confirmation alert (localized title, body, and buttons). The alert's body SHALL include the newly-selected weekday name as an interpolated argument.

The system SHALL commit the candidate value to `AppSettings.weekStartDay` only when the user activates the alert's "Change" (confirmation) button. Activating the alert's "Cancel" (cancel-role) button SHALL discard the candidate value with no write. Dismissing the alert by any other means SHALL also discard the candidate value.

Persistence and sync of `AppSettings.weekStartDay` are governed by the `app-settings` capability and by F-5.01.

#### Scenario: Picking the same value as currently set

- **WHEN** the picker reports a selection equal to the current `AppSettings.weekStartDay`
- **THEN** the system SHALL NOT present the confirmation alert and SHALL NOT write to `AppSettings`.

#### Scenario: Confirming a new week-start

- **WHEN** the user picks a different weekday and taps the "Change" alert button
- **THEN** the system SHALL set `AppSettings.weekStartDay` to the picked value (which persists per the `app-settings` capability) and SHALL clear the candidate state.

#### Scenario: Cancelling a new week-start

- **WHEN** the user picks a different weekday and taps the "Cancel" alert button (or dismisses the alert without confirming)
- **THEN** the system SHALL discard the candidate value, leave `AppSettings.weekStartDay` unchanged, and the picker SHALL display the original (unchanged) weekday on next render.

---

### Requirement: Display section — currency display preference picker

The Settings screen SHALL include a "Display" section that contains a menu-style `Picker` bound to `AppSettings.currencyDisplay` (capability: `app-settings`). The picker SHALL list every `CurrencyDisplayPreference` case (`symbol`, `code`, `codeAndSymbol`) and SHALL render each row in the form `"<localized label> — <example>"` where:

- `<localized label>` is the case's localized human-readable name ("Symbol", "Code", "Code + Symbol" in en).
- `<example>` is a **locale-aware live preview** produced by routing a fixed sentinel `Decimal` (specifically `Decimal(25)`) through `Decimal.formatted(currencyCode:display:locale:)` with `currencyCode = Locale.autoupdatingCurrent.currency?.identifier ?? "USD"` and `display` set to the case under render. This guarantees the picker preview is exactly what the user will see for each preference in their own locale.

Setting the picker SHALL write the new value directly to `AppSettings.currencyDisplay` (no confirmation alert; this preference is non-destructive and reversible). Persistence and sync are governed by the `app-settings` capability.

`CurrencyDisplayPreference` SHALL be the canonical preference symbol consumed by `Decimal.formatted(currencyCode:display:locale:)` so that every monetary render across the app reflects the user's chosen preference.

#### Scenario: Selecting Symbol preference

- **WHEN** the user selects the "Symbol" row (its example reflects the user's locale's currency in symbol form, e.g., `"$25.00"` in en_US, `"25,00 €"` in fr_FR, `"￥25"` in ja_JP) from the Currency Display picker
- **THEN** the system SHALL set `AppSettings.currencyDisplay = .symbol`.

#### Scenario: Selecting Code preference

- **WHEN** the user selects the "Code" row (its example reflects the user's locale's currency in ISO-code form, e.g., `"USD 25.00"` in en_US, `"EUR 25,00"` in fr_FR, `"JPY 25"` in ja_JP) from the Currency Display picker
- **THEN** the system SHALL set `AppSettings.currencyDisplay = .code`.

#### Scenario: Selecting Code + Symbol preference

- **WHEN** the user selects the "Code + Symbol" row (its example reflects the user's locale's currency as `<ISO code> <localized symbol form>`, e.g., `"USD $25.00"` in en_US, `"EUR 25,00 €"` in fr_FR, `"JPY ￥25"` in ja_JP) from the Currency Display picker
- **THEN** the system SHALL set `AppSettings.currencyDisplay = .codeAndSymbol`.

#### Scenario: Picker examples reflect the user's locale

- **WHEN** the device locale is e.g. `fr_FR` with currency EUR
- **THEN** the picker's three example strings SHALL be the live formatter output for `Decimal(25)` against the EUR ISO code and the current locale, one per `CurrencyDisplayPreference` (e.g., `"25,00 €" / "EUR 25,00" / "EUR 25,00 €"`), and SHALL NOT be the en_US literals `"$25" / "USD 25" / "USD $25"`.

#### Scenario: Picker examples fall back to USD when locale has no currency

- **WHEN** the device's `Locale.autoupdatingCurrent.currency?.identifier` returns `nil`
- **THEN** the picker SHALL use `"USD"` as the example currency code (per F-3.04), rendering `Decimal(25)` against USD with the user's other locale formatting rules in effect.

#### Scenario: External change reflected in the picker

- **WHEN** another iCloud-paired device writes a new currency-display preference and the change propagates to this device while `SettingsView` is open
- **THEN** the picker SHALL update to display the new selection (driven by `AppSettings`'s `@Observable` change emission and external-change observer).

---

### Requirement: iCloud Sync Status — tri-state derivation

The Settings screen SHALL include an "iCloud Sync" section that displays a single status row reflecting whether the app's data is currently syncing via iCloud. The row's state SHALL be derived from a `SyncStatus` value injected into the SwiftUI environment.

`SyncStatus` SHALL carry two pieces of state:

- `containerBacking` — set once at app launch from the outcome of `simple_recurring_budgetsApp.makeProductionModelContainer`. Values: `cloudKit` when the SwiftData `ModelContainer` was constructed with `cloudKitDatabase: .automatic`; `localFallback` when CloudKit container construction failed and the app fell back to `cloudKitDatabase: .none`. This value SHALL NOT change at runtime.
- `accountStatus` — initialized to `.checking`; updated by `SettingsView` from `CKContainer.default().accountStatus()` and from observers of `CKAccountChangedNotification` and `NSUbiquityIdentityDidChange` while the screen is alive. Values: `.checking`, `.available`, `.unavailable`.

The row's view-state SHALL be derived from `(containerBacking, accountStatus)` using exactly this mapping:

| `containerBacking` | `accountStatus` | Row view-state |
|---|---|---|
| any | `.checking` | `checking` |
| `.cloudKit` | `.available` | `available` |
| `.cloudKit` | `.unavailable` | `unavailable` |
| `.localFallback` | `.available` | `paused` |
| `.localFallback` | `.unavailable` | `unavailable` |

The four view-states SHALL each render a distinct row composition (icon + label) plus, when applicable, a section footer:

- `checking` — neutral progress indicator with a "Checking…" label and an accessibility label that announces the loading state.
- `available` — green `checkmark.icloud` SF Symbol with an "iCloud Sync is Active" label and an accessibility label that announces "iCloud sync is active".
- `unavailable` — orange `xmark.icloud` SF Symbol with an "iCloud Not Available" label, an accessibility label announcing the state plus guidance, and a section footer guiding the user to sign in via the system Settings app.
- `paused` — distinct icon (proposed: `exclamationmark.icloud` in orange) with a "Sync paused / local only" style label, a fully descriptive accessibility label, and a distinct section footer explaining the cause and the user's recourse. The exact English source strings for this state are gated on user approval before implementation per the change's design and tasks.

The accessibility labels for `available`, `unavailable`, and `checking` rows SHALL match the existing localized strings in `Localizable.xcstrings` exactly; this requirement does not introduce changes to those strings.

#### Scenario: Initial load shows checking

- **WHEN** `SettingsView` first appears and `SyncStatus.accountStatus == .checking`
- **THEN** the iCloud row SHALL render the `checking` composition (neutral label and progress indicator) regardless of `containerBacking`.

#### Scenario: CloudKit-backed and signed in

- **WHEN** `containerBacking == .cloudKit` and `accountStatus == .available`
- **THEN** the iCloud row SHALL render the `available` composition with the "iCloud Sync is Active" label and the green `checkmark.icloud` icon, and the section footer SHALL be empty.

#### Scenario: CloudKit-backed and signed out

- **WHEN** `containerBacking == .cloudKit` and `accountStatus == .unavailable`
- **THEN** the iCloud row SHALL render the `unavailable` composition with the existing "iCloud Not Available" label and the orange `xmark.icloud` icon, and the section SHALL display the existing "Sign in to iCloud in Settings…" footer.

#### Scenario: Local-only fallback while signed in (paused)

- **WHEN** `containerBacking == .localFallback` and `accountStatus == .available`
- **THEN** the iCloud row SHALL render the `paused` composition (distinct from `available` and `unavailable`), and the section SHALL display the `paused` footer copy. The row SHALL NOT claim that iCloud sync is active.

#### Scenario: Local-only fallback while signed out

- **WHEN** `containerBacking == .localFallback` and `accountStatus == .unavailable`
- **THEN** the iCloud row SHALL render the `unavailable` composition (the user's primary problem is the missing account); the `paused` composition is reserved for the signed-in-but-no-CloudKit case.

#### Scenario: Account change updates the row while the sheet is open

- **WHEN** an iCloud account change occurs (`CKAccountChangedNotification` or `NSUbiquityIdentityDidChange`) while `SettingsView` is presented
- **THEN** the system SHALL re-query `CKContainer.default().accountStatus()` and update `SyncStatus.accountStatus`, and the iCloud row SHALL re-render to reflect the new view-state without requiring the user to dismiss and reopen the sheet.

---

### Requirement: Support section — feedback, rate, privacy

The Settings screen SHALL include a "Support" section that contains exactly three rows in this order:

1. **Send Feedback** — a SwiftUI `Link` whose destination is a `mailto:` URL composed from the app's static feedback email (`AppInfo.feedbackEmail`) and a percent-encoded subject (`AppInfo.feedbackSubject`). The row SHALL include a localized accessibility hint indicating the action ("Opens a new email to send feedback about the app").
2. **Rate the App** — a `Button` whose action invokes `@Environment(\.requestReview)`, presenting Apple's StoreKit review prompt. The row SHALL include a localized accessibility hint ("Opens the App Store rating prompt").
3. **Privacy Policy** — a SwiftUI `Link` whose destination is the URL string in `AppInfo.privacyPolicyURL`. The row SHALL include a localized accessibility hint ("Opens the privacy policy in your browser").

The destination of the **Privacy Policy** link is intentionally a placeholder (`https://example.com/privacy`, marked with a `// TODO` in the source) and SHALL NOT be replaced as part of this capability. Resolving the real URL is out of scope; the `// TODO` SHALL remain in source until a separate change addresses it.

If the device has no `mailto:` handler installed, the Send Feedback `Link` MAY no-op when activated. This edge case is acknowledged and accepted; the screen SHALL NOT add a fallback flow for it as part of this capability.

#### Scenario: Send Feedback opens the mail composer

- **WHEN** the user taps the **Send Feedback** row on a device with a `mailto:` handler installed
- **THEN** the system SHALL open the mail handler with the recipient set to `AppInfo.feedbackEmail` and the subject prefilled with `AppInfo.feedbackSubject`.

#### Scenario: Rate the App invokes requestReview

- **WHEN** the user taps the **Rate the App** row
- **THEN** the system SHALL invoke `@Environment(\.requestReview)`, presenting the StoreKit review prompt (subject to Apple's rate-limiting rules; the row SHALL still attempt the call regardless of whether Apple chooses to display the prompt).

#### Scenario: Privacy Policy opens the configured URL

- **WHEN** the user taps the **Privacy Policy** row
- **THEN** the system SHALL open the URL in `AppInfo.privacyPolicyURL` via the system browser. The placeholder destination is acknowledged.

---

### Requirement: About section — app version and build

The Settings screen SHALL include an "About" section that contains a single row displaying the app's version and build numbers, formatted as `"<version> (<build>)"`. The values SHALL be read from `Bundle.main.infoDictionary["CFBundleShortVersionString"]` and `Bundle.main.infoDictionary["CFBundleVersion"]` respectively. If either value is missing, the row SHALL display the em-dash placeholder `"—"` for that field.

The row SHALL be a single `accessibilityElement(children: .combine)`-collapsed element with a localized VoiceOver label that announces both the version and the build number as a single utterance ("Version <version>, build <build>").

#### Scenario: Both version and build present

- **WHEN** `CFBundleShortVersionString` is `"1.0"` and `CFBundleVersion` is `"42"`
- **THEN** the About row SHALL display `"1.0 (42)"` and the VoiceOver label SHALL announce "Version 1.0, build 42".

#### Scenario: Missing build number

- **WHEN** `CFBundleVersion` is missing or `nil`
- **THEN** the About row SHALL display the build portion as `"—"` (the version portion follows the same fallback rule independently).

---

### Requirement: AppSettings binding and environment dependency

`SettingsView` SHALL access app-wide preferences via `@Environment(AppSettings.self)` and SHALL bind controls using SwiftUI's `@Bindable` conversion (`@Bindable var settings = settings`) so that two-way control bindings (e.g., the carry-over toggle, the currency-display picker) write directly back to `AppSettings`. The screen SHALL NOT instantiate its own `AppSettings`; it SHALL consume the shared instance injected from the app entry point.

`SettingsView` SHALL also access `SyncStatus` via `@Environment(SyncStatus.self)` for the iCloud row's view-state derivation. The screen SHALL NOT instantiate its own `SyncStatus`.

#### Scenario: Shared AppSettings consumed

- **WHEN** `SettingsView` reads `@Environment(AppSettings.self)`
- **THEN** it SHALL receive the same `AppSettings` instance that was injected from `simple_recurring_budgetsApp` and that `BudgetsView` / `BudgetRowView` also consume.

#### Scenario: Shared SyncStatus consumed

- **WHEN** `SettingsView` reads `@Environment(SyncStatus.self)`
- **THEN** it SHALL receive the same `SyncStatus` instance that was constructed at app launch from the production `ModelContainer` outcome.

---

### Requirement: No new ViewModel; transient state stays in the view

`SettingsView` SHALL NOT introduce a separate `@Observable` view model. The only transient `@State` the view SHALL own is:

- `pendingWeekStart: Weekday?` — the candidate week-start value awaiting confirmation.

All other state SHALL be derived from `AppSettings` (preferences) or `SyncStatus` (sync availability) via the environment.

This requirement codifies the §2.1 architecture choice in `docs/tech-design-doc.md` ("View + Services, ViewModels on demand"): none of the four escalation triggers (non-trivial draft state, async/Task work beyond a single call, multi-step user actions, expensive derived state) apply at the screen level.

#### Scenario: No SettingsViewModel exists

- **WHEN** any reviewer / future contributor inspects `simple-recurring-budgets/Views/SettingsView.swift` and the surrounding folders
- **THEN** there SHALL NOT be a `SettingsViewModel` (or equivalently-named) `@Observable` class associated with the screen.
