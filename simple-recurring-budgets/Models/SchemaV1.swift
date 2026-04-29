import SwiftData

/// The initial SwiftData schema version containing `Budget` and `ExpenseItem`.
///
/// All future schema migrations will reference this as their baseline.
enum SchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)
  /// Single source of truth for persisted model types. Add new `@Model` types here only.
  static let models: [any PersistentModel.Type] = [Budget.self, ExpenseItem.self]

  /// Runtime `Schema` for the app and tests — always derived from `models` via the versioned schema.
  static var swiftDataSchema: Schema {
    Schema(versionedSchema: Self.self)
  }
}
