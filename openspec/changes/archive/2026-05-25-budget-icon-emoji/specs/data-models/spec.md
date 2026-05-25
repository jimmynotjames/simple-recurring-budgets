## ADDED Requirements

### Requirement: Budget icon attribute

The `Budget` entity SHALL define an optional stored property `icon: String?` (default `nil`) that holds the budget's decorative icon. By convention the value is a single emoji grapheme; the value is supplied by the icon picker (see the `budget-icon` capability) and is not otherwise validated by the model. The property SHALL be stored as `String?` for CloudKit optionality and SHALL persist and sync like other `Budget` attributes. `Budget.init` SHALL accept an `icon: String? = nil` parameter that defaults to `nil`.

This is an additive, optional attribute: it requires no migration plan (the schema is updated in place per the unreleased/greenfield convention) and existing budgets without a value SHALL read as `nil`.

#### Scenario: Default icon on Budget creation

- **WHEN** a `Budget` is initialized with no `icon` argument
- **THEN** its `icon` SHALL be `nil`

#### Scenario: Icon supplied at creation

- **WHEN** a `Budget` is initialized with `icon: "☕"`
- **THEN** its `icon` SHALL be `"☕"` and SHALL persist on save and round-trip through SwiftData

#### Scenario: Icon is optional for CloudKit

- **WHEN** the `Budget` model is described for CloudKit sync
- **THEN** `icon` SHALL be an optional field so the record type remains CloudKit-compatible
