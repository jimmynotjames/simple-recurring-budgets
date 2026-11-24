import Foundation

// MARK: - BudgetInactiveReason

/// Presentation classifier for budgets that aren't running: collapses
/// `BudgetLifecycleState` into "inactive, and why" with the chip's date payload
/// (`.active` maps to `nil`). Drives the dimmed amount, full-width `RemainingBar`, and
/// `InactiveStatusChip`. Action gating reads `lifecycleState` directly, not this type.
enum BudgetInactiveReason: Equatable {
  case preStart(startDate: Date)
  case paused(since: Date)
  case postEnd(endDate: Date)
}

extension BudgetInactiveReason {
  /// Derives the inactive reason from the lifecycle result and budget; `nil` when active.
  /// Dates come from `pausedSince` (lifecycle result) or `startDate` / `endDate` (budget).
  ///
  /// Defensive nil-date fallback: if the date is unexpectedly `nil` for its state (e.g.
  /// `.preStart` via clock skew against `createdAt` with `startDate` unset), returns `nil`
  /// and the row renders as active. Keeping state and dates in sync is the lifecycle
  /// service's job; see `BudgetLifecycleService.pausedSinceDate(from:now:)` for `.paused`.
  static func from(
    lifecycle: BudgetLifecycleResult,
    budget: Budget
  ) -> BudgetInactiveReason? {
    switch lifecycle.lifecycleState {
    case .active:
      return nil
    case .preStart:
      guard let startDate = budget.startDate else { return nil }
      return .preStart(startDate: startDate)
    case .paused:
      guard let since = lifecycle.pausedSince else { return nil }
      return .paused(since: since)
    case .postEnd:
      guard let endDate = budget.endDate else { return nil }
      return .postEnd(endDate: endDate)
    }
  }
}
