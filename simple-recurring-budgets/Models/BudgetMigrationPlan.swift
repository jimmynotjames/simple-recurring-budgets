//
//  BudgetMigrationPlan.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/11/26.
//

import SwiftData

/// The migration plan for the app's SwiftData schema.
///
/// `stages` is empty for V1; add `MigrationStage` entries here when future
/// schema versions require data transforms.
enum BudgetMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [SchemaV1.self]
    static let stages: [MigrationStage] = []
}
