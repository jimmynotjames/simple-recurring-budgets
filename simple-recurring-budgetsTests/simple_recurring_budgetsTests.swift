//
//  simple_recurring_budgetsTests.swift
//  simple-recurring-budgetsTests
//
//  Created by Jimmy Ho on 4/10/26.
//

import SwiftData
import Testing
@testable import simple_recurring_budgets

struct simple_recurring_budgetsTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test func inMemoryModelContainerDoesNotEnableCloudKit() throws {
        let schema = Schema([Item.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        _ = try ModelContainer(for: schema, configurations: [configuration])
    }
}
