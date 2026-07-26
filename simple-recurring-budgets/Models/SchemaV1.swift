import SwiftData

/// The initial SwiftData schema version containing all model types.
///
/// All future schema migrations reference this as their baseline.
///
/// **Frozen.** These record types shipped in v1.0 and are deployed to the CloudKit
/// production environment, so this version must not be edited in place. Any change to a
/// persisted model adds a new `VersionedSchema` (`SchemaV2`, …) plus a `MigrationStage` in
/// `BudgetMigrationPlan` and a migration test. See `docs/tech-design-doc.md` §3.3.
enum SchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)
  /// Single source of truth for persisted model types. Add new `@Model` types here only.
  static let models: [any PersistentModel.Type] = [
    Budget.self,
    ExpenseItem.self,
    AllocationChange.self,
    LifecycleEvent.self,
  ]

  /// Runtime `Schema` for the app and tests — always derived from `models` via the versioned schema.
  static var swiftDataSchema: Schema {
    Schema(versionedSchema: Self.self)
  }
}
