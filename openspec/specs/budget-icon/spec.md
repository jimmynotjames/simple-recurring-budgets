# Budget icon

Optional per-budget decorative emoji icon. Synced from change `budget-icon-emoji` (2026-05-25).

## Requirements

### Requirement: Optional per-budget icon

Each Budget SHALL support an optional icon: a single emoji chosen from a curated set the app provides. The icon is decorative and OPTIONAL — a Budget with no icon SHALL be fully valid and SHALL render name-only. The user SHALL be able to set, change, or remove the icon at any time via the Add/Edit Budget screen.

#### Scenario: Budget created without an icon

- **WHEN** a Budget is created and the user does not choose an icon
- **THEN** the Budget's icon SHALL be unset (`nil`) and every surface SHALL render the budget name with no icon prefix

#### Scenario: User selects an icon

- **WHEN** the user picks an emoji from the curated picker
- **THEN** that emoji SHALL become the Budget's icon and SHALL be persisted on Save

#### Scenario: User removes an existing icon

- **WHEN** a Budget has an icon and the user chooses to remove it in the picker
- **THEN** the Budget's icon SHALL be cleared (`nil`) on Save and surfaces SHALL revert to name-only

---

### Requirement: Curated emoji set sourced from code

The icon picker SHALL present a curated, budget-relevant set of emoji defined in application code. The picker component SHALL be the single master source for the set; the set SHALL NOT be enumerated in specs or product docs (to avoid drift). Picker entries SHALL be unique.

#### Scenario: Picker presents the curated set

- **WHEN** the icon picker is opened
- **THEN** it SHALL display the curated emoji set from code in a scrollable grid, each emoji selectable

---

### Requirement: Icon selection control on the Add/Edit Budget screen

The Add/Edit Budget screen SHALL present an icon-selection control adjacent to the name field. The control SHALL show the currently chosen icon, or a placeholder affordance when none is set, and SHALL open the curated icon picker. The chosen icon SHALL be persisted to the `Budget` entity on Save for both create and edit flows, including when the icon is the only changed field.

#### Scenario: Add an icon while creating a budget

- **WHEN** the user opens the icon picker on the Add Budget screen, selects an emoji, and saves
- **THEN** the newly created Budget SHALL persist the selected emoji as its icon

#### Scenario: Change an icon while editing a budget

- **WHEN** the user changes the icon on the Edit Budget screen and saves
- **THEN** the Budget's persisted icon SHALL be updated to the new value and `lastModified` SHALL be bumped

#### Scenario: Editing only the icon still saves

- **WHEN** the user changes only the icon (no other field) and taps Save
- **THEN** the change SHALL be persisted (the icon difference SHALL satisfy the save-needed gate)

---

### Requirement: Icon display on the Budgets list

On the Budgets screen, each budget row SHALL display the budget's icon (when set) as a prefix of the budget name, separated by a single space so it reads as part of the name. When no icon is set, the row SHALL render the name alone. The icon SHALL be treated as decorative: it SHALL NOT be announced by VoiceOver as part of the row, which announces the budget name and status via the row's existing accessibility label.

#### Scenario: Row with an icon

- **WHEN** a budget with an icon is shown in the list
- **THEN** the row SHALL render the icon immediately before the name with a single-space gap

#### Scenario: Row without an icon

- **WHEN** a budget without an icon is shown in the list
- **THEN** the row SHALL render the name with no leading icon or extra leading space

#### Scenario: VoiceOver does not announce the decorative icon

- **WHEN** VoiceOver focuses a budget row
- **THEN** the announced label SHALL be the budget's existing composed label (name + status) and SHALL NOT include the decorative icon

---

### Requirement: Icon display on the Budget detail screen

On the Budget detail screen, the navigation title SHALL be prefixed with the budget's icon (when set), separated by a single space; when no icon is set, the title SHALL be the budget name alone.

#### Scenario: Detail title with an icon

- **WHEN** the Budget detail screen is shown for a budget that has an icon
- **THEN** the navigation title SHALL be the icon followed by a single space and the budget name

#### Scenario: Detail title without an icon

- **WHEN** the Budget detail screen is shown for a budget with no icon
- **THEN** the navigation title SHALL be the budget name alone

---

### Requirement: Accessibility of the icon chip and picker

The icon-selection chip and the picker SHALL be accessible. The chip SHALL expose a localized accessibility label, a value reflecting the current icon (or a localized "None"), and a hint describing that it opens a picker. Each picker emoji SHALL be an accessible control labeled by its emoji, and the currently selected emoji SHALL carry the selected trait.

#### Scenario: Icon chip accessibility

- **WHEN** VoiceOver focuses the icon chip
- **THEN** it SHALL announce a localized label, the current icon value (or "None"), and a hint that activating it opens a picker

#### Scenario: Selected picker item carries the selected trait

- **WHEN** the picker is open and a budget already has an icon
- **THEN** the matching emoji SHALL be marked selected for assistive technologies

---

### Requirement: Localized strings for icon UI

All user-facing strings introduced for the icon feature (picker title, cancel, remove; icon chip accessibility label, value, and hint) SHALL be defined as localized string-catalog keys with translator comments, and SHALL be translated for all supported App Store storefront locales before release. No hard-coded user-facing English literals SHALL ship in production views for this feature.

#### Scenario: New strings are keyed and translatable

- **WHEN** the icon UI renders any user-facing string
- **THEN** that string SHALL resolve from a localized catalog key (not a hard-coded literal) and SHALL have translations available for all supported locales

---

### Requirement: No analytics for icon changes

Choosing, changing, or removing a budget icon is a cosmetic action and SHALL NOT emit a new analytics event or property. An icon change MAY contribute only to the existing aggregate "budget edited" change gate, consistent with the analytics scope (F-8.02).

#### Scenario: Editing an icon emits no new analytics

- **WHEN** the user changes a budget's icon and saves
- **THEN** no new icon-specific analytics event or property SHALL be emitted; only the existing `budget_edited` event MAY fire as it already would for any edit
