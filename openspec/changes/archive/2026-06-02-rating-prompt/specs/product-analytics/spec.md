## ADDED Requirements

### Requirement: Rating-prompt analytics events

The analytics client SHALL define and the app SHALL emit two consent-gated rating-prompt events, carrying only categorical/bucketed values (no PII, per the §5 privacy contract):

- `rating_prompt_eligible` — fired **once per user**, the first time the eligibility thresholds (excluding the once-per-version guard) are met. Gated by the `rating_prompt_first_eligible_at` people property so it never fires twice.
- `rating_prompt_requested` — fired when the app calls `requestReview`. De-duplicated per app version (matching the once-per-version guard). Carries `time_since_first_eligible_bucket` (`<1d` / `<7d` / `<30d` / `≥30d`).

The previously-planned `rating_prompt_shown` and `rating_prompt_resolved` events SHALL NOT be emitted — the native `requestReview` API reports neither presentation nor outcome, so no `outcome` value is observable. No custom pre-prompt SHALL be added to manufacture such a signal.

#### Scenario: Eligible event fires once

- **WHEN** the user first meets the eligibility thresholds
- **THEN** `rating_prompt_eligible` is tracked and `rating_prompt_first_eligible_at` is set
- **AND** subsequent eligible logs do not re-fire `rating_prompt_eligible`

#### Scenario: Requested event fires when a review is requested

- **WHEN** the app calls `requestReview` for the current app version
- **THEN** `rating_prompt_requested` is tracked with `time_since_first_eligible_bucket`
- **AND** the `rating_prompt_last_requested_at` people property is refreshed

#### Scenario: Events are dropped when opted out

- **WHEN** analytics opt-in is `false`
- **THEN** neither `rating_prompt_eligible` nor `rating_prompt_requested` is transmitted (eligibility tracking itself still functions)

#### Scenario: No outcome is ever transmitted

- **WHEN** a review has been requested
- **THEN** no `rating_prompt_shown`, `rating_prompt_resolved`, or `outcome`-style property is emitted
