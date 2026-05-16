## MODIFIED Requirements

### Requirement: VersionedSchema V1 baseline

The system SHALL define a `SchemaV1` conforming to `VersionedSchema` that contains the `Budget`, `ExpenseItem`, `AllocationChange`, and `LifecycleEvent` model definitions. This establishes the baseline version for all future schema migrations. The app has not been deployed to the App Store, so updating this baseline in place (rather than adding a `SchemaV2`) is the correct shape for the rewrite (briefing §1).

#### Scenario: V1 schema contains all four models

- **WHEN** `SchemaV1.models` is inspected
- **THEN** it SHALL contain `Budget.self`, `ExpenseItem.self`, `AllocationChange.self`, and `LifecycleEvent.self`

#### Scenario: V1 version identifier

- **WHEN** `SchemaV1.versionIdentifier` is inspected
- **THEN** it SHALL return a `Schema.Version` of `(1, 0, 0)`

### Requirement: SchemaMigrationPlan baseline

The system SHALL define a `BudgetMigrationPlan` conforming to `SchemaMigrationPlan` that references `SchemaV1` as its only schema. The migration plan's `stages` array SHALL be empty (no migrations exist yet). The plan is preserved (not deleted) so that future schema bumps have a starting point; this change SHALL NOT introduce `SchemaV2` or any `MigrationStage` entries.

#### Scenario: Migration plan with single schema version

- **WHEN** `BudgetMigrationPlan.schemas` is inspected
- **THEN** it SHALL contain exactly `[SchemaV1.self]`

#### Scenario: No migration stages

- **WHEN** `BudgetMigrationPlan.stages` is inspected
- **THEN** it SHALL be an empty array

#### Scenario: No SchemaV2 introduced by the rewrite

- **WHEN** the project is inspected after the rewrite ships
- **THEN** no `SchemaV2` type exists and `BudgetMigrationPlan.schemas` still contains exactly `[SchemaV1.self]`

## Doc alignment

No changes to `docs/main-prd.md`, `docs/product-features-planning.md`, or `docs/tech-design-doc.md` are required by this delta beyond what the `data-models` delta already covers. No conflicts.
