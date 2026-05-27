import Foundation

extension Budget {
  /// An `Equatable` snapshot of every field that the lifecycle math depends on —
  /// the budget's own `lastModified` / `lastResetDate` plus the count and latest
  /// `lastModified` of each child collection (expenses, allocation changes,
  /// lifecycle events).
  ///
  /// **Why this exists (issue #127).** Views cache the expensive
  /// `BudgetLifecycleService.result(for:)` walk in `@State` and refresh it on a few
  /// triggers. A local write always bumps `Budget.lastModified`, so observing that
  /// alone was enough on-device. But a CloudKit remote merge imports child rows
  /// (a new `ExpenseItem`, an edited `AllocationChange`, …) and the parent's
  /// `lastModified` bump in **separate** transactions that arrive in arbitrary
  /// order. Once a `lastModified`-driven recompute fires, a later-arriving expense
  /// never re-triggers it, leaving the displayed Remaining stale (e.g. $50 instead
  /// of $45).
  ///
  /// Reading this token inside a view's `body` (via `.onChange(of:)`) subscribes the
  /// view — through SwiftData's `@Observable` conformance — to the child collections
  /// as well as `lastModified`. The token therefore changes, and the view recomputes,
  /// exactly when SwiftUI re-renders with the merged remote data, regardless of which
  /// transaction delivered which row.
  ///
  /// Count catches inserts and deletes; the latest child `lastModified` catches
  /// in-place edits (every write path bumps the edited row's `lastModified` to the
  /// current instant, so the max strictly advances).
  var recomputeToken: RecomputeToken {
    RecomputeToken(
      lastModified: lastModified,
      lastResetDate: lastResetDate,
      expenseCount: expenseItems.count,
      latestExpenseModified: expenseItems.map(\.lastModified).max(),
      allocationCount: allocationChanges.count,
      latestAllocationModified: allocationChanges.map(\.lastModified).max(),
      lifecycleEventCount: lifecycleEvents.count,
      latestLifecycleEventModified: lifecycleEvents.map(\.lastModified).max()
    )
  }

  /// Value type backing `Budget.recomputeToken`. See that property for the rationale.
  struct RecomputeToken: Equatable {
    let lastModified: Date
    let lastResetDate: Date?
    let expenseCount: Int
    let latestExpenseModified: Date?
    let allocationCount: Int
    let latestAllocationModified: Date?
    let lifecycleEventCount: Int
    let latestLifecycleEventModified: Date?
  }
}
