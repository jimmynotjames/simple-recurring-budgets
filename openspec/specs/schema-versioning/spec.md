# Schema versioning

SwiftData `VersionedSchema` baseline and migration plan. Synced from change `data-architecture` (2026-04-11).

## Requirements

### Requirement: VersionedSchema V1 baseline

The system SHALL define a `SchemaV1` conforming to `VersionedSchema` that contains the `Budget` and `ExpenseItem` model definitions. This establishes the baseline version for all future schema migrations.

#### Scenario: V1 schema contains both models
- **WHEN** `SchemaV1.models` is inspected
- **THEN** it SHALL contain `Budget.self` and `ExpenseItem.self`.

#### Scenario: V1 version identifier
- **WHEN** `SchemaV1.versionIdentifier` is inspected
- **THEN** it SHALL return a `Schema.Version` of `(1, 0, 0)`.

---

### Requirement: SchemaMigrationPlan baseline

The system SHALL define a `BudgetMigrationPlan` conforming to `SchemaMigrationPlan` that references `SchemaV1` as its only schema. The migration plan's `stages` array SHALL be empty (no migrations exist yet).

#### Scenario: Migration plan with single schema version
- **WHEN** `BudgetMigrationPlan.schemas` is inspected
- **THEN** it SHALL contain exactly `[SchemaV1.self]`.

#### Scenario: No migration stages
- **WHEN** `BudgetMigrationPlan.stages` is inspected
- **THEN** it SHALL be an empty array.
