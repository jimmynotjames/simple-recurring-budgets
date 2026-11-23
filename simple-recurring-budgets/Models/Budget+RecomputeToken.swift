import Foundation

extension Budget {
  /// An `Equatable` snapshot of every field the lifecycle math depends on: the budget's `lastModified` /
  /// `lastResetDate` plus the count and latest `lastModified` of each child collection (expenses, allocation
  /// changes, lifecycle events).
  ///
  /// **Why it exists:** views cache the expensive `BudgetLifecycleService.result(for:)` walk in `@State`. A
  /// local write bumps `Budget.lastModified`, but a CloudKit remote merge imports child rows and the parent's
  /// `lastModified` bump in **separate** transactions in arbitrary order. After a `lastModified`-driven
  /// recompute, a later-arriving expense would never re-trigger it, leaving Remaining stale (e.g. $50
  /// instead of $45).
  ///
  /// Reading the token in a view's `body` (via `.onChange(of:)`) subscribes the view, through SwiftData's
  /// `@Observable`, to the child collections too, so it recomputes exactly when SwiftUI re-renders with the
  /// merged data, whichever transaction delivered which row.
  ///
  /// Count catches inserts and deletes; the latest child `lastModified` catches in-place edits (every write
  /// path bumps the edited row's `lastModified` to now, so the max strictly advances).
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
