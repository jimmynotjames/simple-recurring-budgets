## ADDED Requirements

### Requirement: Successful Add-mode log feeds the rating-prompt coordinator

On a successful **Add-mode** expense save, the Add/Edit Expense screen SHALL notify the rating-prompt coordinator, passing whether the parent budget is in the active lifecycle state and whether the budget's current-period Remaining (computed from the existing budget calculator) is non-deficit after the save. This notification MUST occur only for successful Add-mode logs — not for edits, deletes, or save failures — and MUST NOT change the existing save, `expense_logged`, dismissal, or error-handling behavior.

#### Scenario: Add-mode save notifies the coordinator

- **WHEN** the user saves a new expense in Add mode and the save succeeds
- **THEN** the rating-prompt coordinator is notified with the active-state and non-deficit flags for the parent budget

#### Scenario: Edit-mode save does not notify the coordinator

- **WHEN** the user saves changes to an existing expense in Edit mode
- **THEN** the rating-prompt coordinator is not notified

#### Scenario: Failed save does not notify the coordinator

- **WHEN** an Add-mode save throws a persistence error
- **THEN** the rating-prompt coordinator is not notified and existing error handling is unchanged
