## MODIFIED Requirements

### Requirement: Add/Edit/View Expense screen toolbar items differ by mode

The Add/Edit/View Expense screen SHALL expose toolbar items according to the active mode:

- **Add mode** (`viewModel.isEditing == false`): a leading Cancel button (key `addEditExpense.action.cancel`, placement `.cancellationAction`) that dismisses without persisting any changes, and a trailing Save button (key `addEditExpense.action.save`, placement `.confirmationAction`) whose enablement follows the "Save is enabled only when amount is strictly positive" requirement.
- **Edit/View mode** (`viewModel.isEditing == true`): a trailing Save button only. The Cancel button SHALL NOT be rendered. The system-provided back button in the `NavigationStack` serves as the discard path — navigating back without tapping Save discards any in-flight field changes.

The Save button SHALL render with `.fontWeight(.semibold)` in both modes. The Cancel button locale key `addEditExpense.action.cancel` remains in the String Catalog (it is used in Add mode); it is simply not rendered in Edit mode.

No other toolbar items SHALL be present on this screen in either mode.

#### Scenario: Add mode shows Cancel and Save toolbar items

- **WHEN** the sheet is visible in Add mode (`viewModel.isEditing == false`)
- **THEN** the navigation bar SHALL show a leading Cancel button (key `addEditExpense.action.cancel`) and a trailing Save button (key `addEditExpense.action.save`)

#### Scenario: Edit mode shows Save only — no Cancel button

- **WHEN** the screen is pushed in Edit/View mode (`viewModel.isEditing == true`)
- **THEN** the navigation bar SHALL show only the trailing Save button; the leading Cancel button SHALL NOT be present

#### Scenario: Back chevron is the discard path in Edit mode

- **WHEN** the screen is in Edit/View mode and the user navigates back without tapping Save
- **THEN** no changes are persisted; `dismiss()` is NOT called explicitly from a Cancel button; the `NavigationStack` back action pops the view

#### Scenario: Save remains enabled by positive amount in both modes

- **WHEN** `viewModel.amount > 0` in either Add or Edit/View mode
- **THEN** the Save button is enabled regardless of whether Cancel is visible

#### Scenario: Cancel in Add mode dismisses without saving

- **WHEN** the sheet is in Add mode and the user taps Cancel
- **THEN** the sheet is dismissed and no `ExpenseItem` is inserted
