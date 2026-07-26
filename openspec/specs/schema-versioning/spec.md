# Schema versioning

SwiftData `VersionedSchema` baseline and migration plan. Synced from change `rewrite-budget-calculations` (2026-05-15); migration policy updated post-launch (2026-07-26).

## Requirements

### Requirement: VersionedSchema V1 baseline

The system SHALL define a `SchemaV1` conforming to `VersionedSchema` that contains the `Budget`, `ExpenseItem`, `AllocationChange`, and `LifecycleEvent` model definitions. This establishes the baseline version for all future schema migrations.

`SchemaV1` shipped in Wren v1.0 (App Store, 2026-07-22) and its record types are deployed to the CloudKit production environment (2026-07-12). It is therefore a **frozen baseline**: it SHALL NOT be edited in place. Any subsequent change to a persisted model SHALL add a new `VersionedSchema` (`SchemaV2`, …), a corresponding `MigrationStage`, and a migration test. See `docs/tech-design-doc.md` §3.3.

#### Scenario: V1 schema contains all four models

- **WHEN** `SchemaV1.models` is inspected
- **THEN** it SHALL contain `Budget.self`, `ExpenseItem.self`, `AllocationChange.self`, and `LifecycleEvent.self`

#### Scenario: V1 version identifier

- **WHEN** `SchemaV1.versionIdentifier` is inspected
- **THEN** it SHALL return a `Schema.Version` of `(1, 0, 0)`

---

### Requirement: SchemaMigrationPlan baseline

The system SHALL define a `BudgetMigrationPlan` conforming to `SchemaMigrationPlan`. As of v1.0 it references `SchemaV1` as its only schema and its `stages` array is empty, because no migration has been needed yet. The plan exists so that the first post-launch schema change has a starting point: that change SHALL append the new schema version to `schemas` and its `MigrationStage` to `stages`.

#### Scenario: Migration plan with single schema version (v1.0 state)

- **WHEN** `BudgetMigrationPlan.schemas` is inspected while `SchemaV1` is the only shipped schema version
- **THEN** it SHALL contain exactly `[SchemaV1.self]`

#### Scenario: No migration stages (v1.0 state)

- **WHEN** `BudgetMigrationPlan.stages` is inspected while `SchemaV1` is the only shipped schema version
- **THEN** it SHALL be an empty array

#### Scenario: First post-launch schema change

- **WHEN** a change modifies any persisted model after v1.0 shipped
- **THEN** it SHALL add a new `VersionedSchema` rather than editing `SchemaV1`, append that version to `BudgetMigrationPlan.schemas`, append a `MigrationStage` to `BudgetMigrationPlan.stages`, and ship a migration test following the `MigrationTestSupport` pattern
