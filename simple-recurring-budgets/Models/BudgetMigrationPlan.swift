import SwiftData

/// The migration plan for the app's SwiftData schema.
///
/// `stages` is empty because V1 is the only version shipped so far. Now that v1.0 is live
/// with real user data, the first change to a persisted model appends its new
/// `VersionedSchema` to `schemas` and a `MigrationStage` here. See
/// `docs/tech-design-doc.md` §3.3.
enum BudgetMigrationPlan: SchemaMigrationPlan {
  static let schemas: [any VersionedSchema.Type] = [SchemaV1.self]
  static let stages: [MigrationStage] = []
}
