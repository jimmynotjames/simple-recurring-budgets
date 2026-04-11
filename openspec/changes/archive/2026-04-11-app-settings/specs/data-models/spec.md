## MODIFIED Requirements

### Requirement: Carry-over toggle on Budget

Each Budget SHALL have an `isCarryOverEnabled` property (`Bool`, default `true`) that controls whether carry-over is active for that budget. When `false`, carry-over SHALL NOT be computed or displayed for that budget. The default value for new budgets SHALL be sourced from `AppSettings.defaultCarryOverEnabled` at creation time; callers that create a `Budget` SHALL pass the current value explicitly. The `Budget.init` parameter `isCarryOverEnabled` SHALL default to `true` as a safe fallback when `AppSettings` is not available (e.g., in tests or previews).

#### Scenario: New budget inherits global default (enabled)

- **WHEN** a Budget is created and `AppSettings.defaultCarryOverEnabled` is `true`
- **THEN** the Budget's `isCarryOverEnabled` SHALL be `true`.

#### Scenario: New budget inherits global default (disabled)

- **WHEN** a Budget is created and `AppSettings.defaultCarryOverEnabled` is `false`
- **THEN** the caller SHALL pass `isCarryOverEnabled: false` to `Budget.init`, and the Budget's `isCarryOverEnabled` SHALL be `false`.

#### Scenario: Carry-over disabled on existing budget

- **WHEN** a Budget's `isCarryOverEnabled` is set to `false`
- **THEN** the carry-over amount SHALL NOT be computed or displayed for that budget.

#### Scenario: Budget.init does not depend on AppSettings directly

- **WHEN** `Budget.init` is called in a test without an `AppSettings` instance
- **THEN** `isCarryOverEnabled` SHALL default to `true` (the init parameter default), and no runtime error SHALL occur.
