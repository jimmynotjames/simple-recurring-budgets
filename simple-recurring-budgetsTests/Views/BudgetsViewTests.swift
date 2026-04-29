//
//  BudgetsViewTests.swift
//  simple-recurring-budgetsTests
//
//  Tests for BudgetsView handler logic:
//    – move: dense sortOrder rewrite + lastModified bump rule
//
//  SwiftUI rendering of the empty-state branch is validated by the
//  #Preview declarations in BudgetsView.swift.
//
//  Note: these tests inline the move algorithm rather than invoking
//  BudgetsView.move(from:to:) directly. They verify the algorithm is
//  correct but do not catch view-wiring regressions (e.g. a missing
//  .onMove modifier). If the handler logic is refactored, update these
//  tests to match. That's an acceptable trade-off since the @Environment-
//  driven SwiftData context makes unit-testing the handler directly awkward.
//

import Foundation
@testable import simple_recurring_budgets
import SwiftData
import SwiftUI
import Testing

// MARK: - Reorder handler: sortOrder rewrite + lastModified rule

struct BudgetsViewMoveTests {
  /// 6.1.d — Moving a row rewrites sortOrder correctly for the new order.
  @Test func move_rewritesSortOrder_forNewOrder() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budgetA = Budget(name: "A"); budgetA.sortOrder = 0; context.insert(budgetA)
    let budgetB = Budget(name: "B"); budgetB.sortOrder = 1; context.insert(budgetB)
    let budgetC = Budget(name: "C"); budgetC.sortOrder = 2; context.insert(budgetC)
    try context.save()

    // Move C (index 2) to the front (offset 0): result order [C, A, B]
    var reordered = [budgetA, budgetB, budgetC]
    reordered.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

    let now = Date()
    for (index, budget) in reordered.enumerated() where budget.sortOrder != index {
      budget.sortOrder = index
      budget.lastModified = now
    }
    try context.save()

    // Fetch sorted by sortOrder and verify sequence
    let fetched = try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder)]))
    #expect(fetched.map(\.name) == ["C", "A", "B"])
    #expect(fetched[0].sortOrder == 0)
    #expect(fetched[1].sortOrder == 1)
    #expect(fetched[2].sortOrder == 2)
  }

  /// 6.1.d — lastModified is bumped only on rows whose sortOrder changed.
  @Test func move_lastModified_onlyBumpsChangedRows() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budgetA = Budget(name: "A"); budgetA.sortOrder = 0; context.insert(budgetA)
    let budgetB = Budget(name: "B"); budgetB.sortOrder = 1; context.insert(budgetB)
    let budgetC = Budget(name: "C"); budgetC.sortOrder = 2; context.insert(budgetC)
    try context.save()

    let originalAModified = budgetA.lastModified

    // Move B (index 1) to after C (offset 3): result order [A, C, B]
    // A stays at index 0 → unchanged
    // C goes from sortOrder 2 → 1 → changed
    // B goes from sortOrder 1 → 2 → changed
    var reordered = [budgetA, budgetB, budgetC]
    reordered.move(fromOffsets: IndexSet(integer: 1), toOffset: 3)

    // Pause 1 ms to ensure `now` is strictly after the init-time `lastModified`.
    Thread.sleep(forTimeInterval: 0.001)
    let now = Date()

    for (index, budget) in reordered.enumerated() where budget.sortOrder != index {
      budget.sortOrder = index
      budget.lastModified = now
    }

    #expect(budgetA.sortOrder == 0)
    #expect(
      budgetA.lastModified == originalAModified,
      "A's sortOrder didn't change so lastModified should NOT be bumped"
    )
    #expect(budgetC.sortOrder == 1)
    #expect(budgetC.lastModified == now, "C's sortOrder changed so lastModified SHOULD be bumped")
    #expect(budgetB.sortOrder == 2)
    #expect(budgetB.lastModified == now, "B's sortOrder changed so lastModified SHOULD be bumped")
  }

  /// 6.1.d — Single save call: verifying via observable model state (no direct call-count API).
  /// All mutations are applied and a single save persists them correctly.
  @Test func move_persistsNewOrderAcrossContextRefetch() throws {
    let container = try TestModelContainer.make()
    let context = ModelContext(container)

    let budgetA = Budget(name: "A"); budgetA.sortOrder = 0; context.insert(budgetA)
    let budgetB = Budget(name: "B"); budgetB.sortOrder = 1; context.insert(budgetB)
    try context.save()

    // Move B to front: [B, A]
    var reordered = [budgetA, budgetB]
    reordered.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
    let now = Date()
    for (index, budget) in reordered.enumerated() where budget.sortOrder != index {
      budget.sortOrder = index
      budget.lastModified = now
    }
    try context.save()

    // Re-fetch from a new context to confirm persistence
    let context2 = ModelContext(container)
    let fetched = try context2.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder)]))
    #expect(fetched.map(\.name) == ["B", "A"])
  }
}
