import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Budget.icon persistence (F-4.03)

struct BudgetIconModelTests {
  @Test func budget_defaultIconIsNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)
    let budget = Budget()
    context.insert(budget)
    #expect(budget.icon == nil)
  }

  @Test func budget_iconRoundTripsThroughStore() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .daily, icon: "☕")
    context.insert(budget)
    try context.save()

    let fetched = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(fetched.icon == "☕")
  }

  @Test func budget_iconCanBeClearedToNil() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budget = Budget(name: "Coffee", currencyCode: "USD", period: .daily, icon: "☕")
    context.insert(budget)
    try context.save()

    budget.icon = nil
    try context.save()

    let fetched = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
    #expect(fetched.icon == nil)
  }
}

// MARK: - Curated icon set (BudgetIconPicker master source)

struct BudgetIconPickerSetTests {
  @Test func curatedIcons_hasNoDuplicates() {
    let icons = BudgetIconPicker.curatedIcons
    #expect(Set(icons).count == icons.count)
  }

  @Test func curatedIcons_isNonEmpty() {
    #expect(!BudgetIconPicker.curatedIcons.isEmpty)
  }
}
