//
//  SchemaV1.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/11/26.
//

import SwiftData

/// The initial SwiftData schema version containing `Budget` and `ExpenseItem`.
///
/// All future schema migrations will reference this as their baseline.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [Budget.self, ExpenseItem.self]
}
