## ADDED Requirements

### Requirement: Diagnostics & Analytics section

The Settings screen SHALL include a "Diagnostics & Analytics" section, ordered between the existing "iCloud Sync" and "Support" sections. The section SHALL contain a single toggle bound to `AppSettings.analyticsOptIn` (capability: `app-settings`).

The toggle SHALL be tinted with `Color.accentColor` so the picker color follows the app's tint, matching the existing Budgets section's default-carry-over toggle convention.

The section SHALL include a localized footer that:

- Summarizes what is and is not transmitted (mirroring the field-level allow/deny rules in [`docs/analytics-spec.md` §5](../../../docs/analytics-spec.md#5-privacy-contract--pii-and-field-level-rules) in plain language: never any expense field, never any iCloud or Apple ID identifier, only categorical Budget metadata and bucketed counts).
- Notes that the initial state was set automatically based on the device locale and can be changed at any time.

All copy in the section SHALL be keyed in `Localizable.xcstrings` with translator-friendly comments per F-3.03. The required keys are `settings.analytics.section.title`, `settings.analytics.toggle.title`, and `settings.analytics.toggle.footer`. No hard-coded English literal SHALL appear in the new section.

Toggling the switch SHALL drive the `analytics_consent_changed` event flow defined in the `product-analytics` capability:

- **Toggle-on transition** (`false → true`): the system SHALL set `AppSettings.analyticsOptIn = true` (which persists), then `analytics.track("analytics_consent_changed", properties: [new_value: true, old_value: false])` SHALL fire, lazy-initializing the SDK.
- **Toggle-off transition** (`true → false`): the system SHALL fire `analytics.track("analytics_consent_changed", properties: [new_value: false, old_value: true])` FIRST while still opted in, then call `MixpanelAnalyticsClient.reset()`, then set `AppSettings.analyticsOptIn = false` LAST. This ordering ensures the opt-out is observable before subsequent `track` calls are dropped.

The opt-in toggle change SHALL NOT also fire a `setting_changed` event (per the `product-analytics` capability's `setting_changed` requirement, the analytics opt-in is excluded from the `setting_name` enum and uses the dedicated `analytics_consent_changed` event instead).

#### Scenario: Section appears between iCloud Sync and Support

- **WHEN** the user opens `SettingsView`
- **THEN** the Diagnostics & Analytics section SHALL be visible between the iCloud Sync section and the Support section in vertical scroll order

#### Scenario: Toggle reflects current AppSettings.analyticsOptIn value

- **WHEN** `AppSettings.analyticsOptIn` is `false` and the screen renders
- **THEN** the toggle SHALL appear in the off state

#### Scenario: Toggle-on fires consent event after the flip

- **WHEN** the user flips the toggle from off to on
- **THEN** the system SHALL persist `AppSettings.analyticsOptIn = true`, and SHALL fire `analytics_consent_changed` with `new_value: true` (lazy-initializing the SDK on this first opted-in track)

#### Scenario: Toggle-off ordering — consent event fires before reset and before flip

- **WHEN** the user flips the toggle from on to off
- **THEN** the system SHALL fire `analytics_consent_changed` with `new_value: false` FIRST, THEN call `MixpanelAnalyticsClient.reset()`, THEN set `AppSettings.analyticsOptIn = false` — in that exact order

#### Scenario: Toggle change does not fire setting_changed

- **WHEN** the user flips the analytics opt-in toggle
- **THEN** the system SHALL NOT fire `analytics.track("setting_changed", ...)` for this change

#### Scenario: Section uses keyed strings

- **WHEN** a contributor inspects the Diagnostics & Analytics section in `SettingsView`
- **THEN** every visible label (section title, toggle title, footer) SHALL resolve through `Text(...)` / `LocalizedStringKey` against `settings.analytics.section.title` / `settings.analytics.toggle.title` / `settings.analytics.toggle.footer`, with no hard-coded English literal

#### Scenario: External change reflected in the toggle

- **WHEN** another iCloud-paired device writes a new value for `"analyticsOptIn"` and the change propagates to this device while `SettingsView` is open
- **THEN** the toggle SHALL update to the new value (driven by `AppSettings`'s `@Observable` change emission and external-change observer per the `app-settings` capability)
