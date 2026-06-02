## ADDED Requirements

### Requirement: Eligibility-signal tracking

The system SHALL maintain, in the iCloud key-value store (via the existing `KeyValueStore` abstraction) and **independent of analytics consent**, the signals that drive rating-prompt eligibility: the first-launch timestamp, the lifetime count of successful Add-mode expense logs, the count of distinct calendar days on which an expense was logged, the first-eligible timestamp, and the last app version for which a review was requested. These signals MUST NOT reuse `AppSettings.analyticsFirstOpenAt` or any analytics-gated state.

#### Scenario: First launch stamps the install date once

- **WHEN** the rating-prompt state is initialized on a store that has no stored install date
- **THEN** the current date is recorded as the install date and persisted
- **AND** subsequent launches read the stored value without overwriting it

#### Scenario: A successful Add-mode log advances the counters

- **WHEN** the user successfully logs a new expense in Add mode
- **THEN** the lifetime logged-expense count increases by one
- **AND** if the log occurs on a calendar day with no prior recorded log, the distinct-logging-day count increases by one

#### Scenario: Counters persist for users who declined analytics

- **WHEN** analytics opt-in is `false`
- **THEN** the eligibility counters are still read and written normally

### Requirement: Eligibility evaluation (balanced profile)

The system SHALL consider a user eligible for an automatic review request only when ALL of the following hold: install age is at least 7 days, the distinct-logging-day count is at least 3, the lifetime logged-expense count is at least 10, the triggering log left the budget's current period non-deficit (Remaining ≥ 0), and the triggering budget is in the active lifecycle state.

#### Scenario: All thresholds met on a non-deficit active log

- **WHEN** a successful Add-mode log occurs on an active budget whose resulting Remaining is ≥ 0, the install age is ≥ 7 days, distinct logging days ≥ 3, and lifetime logged expenses ≥ 10
- **THEN** the user is eligible

#### Scenario: A deficit-producing log is not a positive moment

- **WHEN** a successful Add-mode log leaves the budget's current period Remaining < 0
- **THEN** the user is not eligible on that log, even if every other threshold is met

#### Scenario: Below a usage threshold

- **WHEN** the lifetime logged-expense count is below 10 (or distinct logging days below 3, or install age below 7 days)
- **THEN** the user is not eligible regardless of the other signals

#### Scenario: Logs on non-active budgets do not qualify

- **WHEN** an expense is logged against a paused, pre-start, or post-end budget
- **THEN** that log does not make the user eligible (though counters may still advance per the tracking requirement)

### Requirement: Once-per-version guard and native request

When a user is eligible AND no review has yet been requested for the current app version (`CFBundleShortVersionString`), the system SHALL request a review using Apple's native `requestReview` (`@Environment(\.requestReview)`) and record the current app version as the last requested version. The system SHALL NOT present a custom rating dialog or pre-prompt. Re-prompt prevention relies on this once-per-version guard layered on Apple's automatic throttling; no logic depends on whether the dialog was shown or on the user's choice.

#### Scenario: Eligible and not yet asked this version

- **WHEN** the user is eligible and the last-requested version differs from the current app version
- **THEN** the system requests a review via the native API
- **AND** records the current app version as the last requested version

#### Scenario: Already asked this version

- **WHEN** the user is eligible but the last-requested version equals the current app version
- **THEN** the system does not request a review

#### Scenario: The version is recorded even though the outcome is unobservable

- **WHEN** the system has requested a review for the current version
- **THEN** no further request is made for that version, regardless of whether StoreKit actually presented the dialog (the native API reports no outcome)

### Requirement: Deferred presentation from a stable context

The system SHALL decouple the eligibility decision from the presentation: an eligible log sets a transient "request pending" signal, and the actual `requestReview` call SHALL be made from the root view only when the scene is active. The request MUST NOT be presented from within the Add Expense sheet's save handler.

#### Scenario: Request is presented after the sheet dismisses

- **WHEN** an eligible Add-mode log sets the request-pending signal and the Add Expense sheet dismisses
- **THEN** the root presenter requests the review once the scene is active
- **AND** clears the pending signal so it is requested at most once per pending decision

#### Scenario: No pending request

- **WHEN** no eligible log has set the pending signal
- **THEN** the root presenter does not request a review
