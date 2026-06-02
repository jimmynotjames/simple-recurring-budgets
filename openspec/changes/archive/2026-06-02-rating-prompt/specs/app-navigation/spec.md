## ADDED Requirements

### Requirement: Root view hosts the rating-prompt presenter

The root view SHALL host the rating-prompt presenter, which reads `@Environment(\.requestReview)` and, when the rating-prompt coordinator has a pending request and the scene phase is active, requests a review via the native API, instructs the coordinator to record the requested version, and clears the pending signal. The presenter MUST be hosted once at the root so it functions regardless of which screen the user returns to after dismissing the Add Expense sheet, and MUST NOT present any custom rating UI.

#### Scenario: Pending request is presented when the scene is active

- **WHEN** the coordinator's request-pending signal is set and the scene phase becomes (or is) active
- **THEN** the root presenter requests a review via `requestReview`
- **AND** the coordinator records the current app version and clears the pending signal

#### Scenario: Presenter is inert without a pending request

- **WHEN** there is no pending request
- **THEN** the root presenter takes no action and presents no UI
