import Foundation

// move(fromOffsets:toOffset:) on MutableCollection is defined by SwiftUI.
import SwiftUI

/// Applies a drag-to-reorder gesture's index change to the budgets list.
/// Extracted from `BudgetsView.move(from:to:)` so unit tests exercise the
/// production algorithm directly with an injected `now` instead of inlining a
/// copy of it (test-coverage-audit-2026-06-10 D1); the view's only remaining
/// responsibility is forwarding the indices and saving.
enum BudgetReorderService {
  /// Rewrites `sortOrder` densely over the new order (0..<count).
  /// Only mutates — and bumps `lastModified` on — rows whose `sortOrder`
  /// actually changed. Does not save; the caller batches the write.
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
