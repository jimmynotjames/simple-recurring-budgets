import Foundation

// move(fromOffsets:toOffset:) on MutableCollection is defined by SwiftUI.
import SwiftUI

/// Applies a drag-to-reorder index change to the budgets list. Extracted from
/// `BudgetsView.move(from:to:)` so tests can run the real algorithm with an injected
/// `now`; the view only forwards indices and saves.
enum BudgetReorderService {
  /// Rewrites `sortOrder` densely (0..<count), mutating and bumping `lastModified` only on
  /// rows whose value changed. Doesn't save; the caller batches the write.
  static func applyMove(
    budgets: [Budget],
    fromOffsets source: IndexSet,
    toOffset destination: Int,
    now: Date
  ) {
    var reordered = budgets
    reordered.move(fromOffsets: source, toOffset: destination)
    for (index, budget) in reordered.enumerated() where budget.sortOrder != index {
      budget.sortOrder = index
      budget.lastModified = now
    }
  }
}
