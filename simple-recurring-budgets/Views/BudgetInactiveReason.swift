import Foundation

// MARK: - BudgetInactiveReason

/// View-layer presentation classifier for budgets that are not currently running.
///
/// Collapses the domain-layer `BudgetLifecycleState` (`.preStart`, `.active`,
/// `.paused`, `.postEnd`) into a single "is this budget inactive, and if so why?"
/// value carrying the date payload the chip needs. `.active` maps to `nil`.
///
/// The view layer uses this enum to drive the unified inactive presentation
/// (dimmed amount, full-width secondary `RemainingBar`, single `InactiveStatusChip`)
/// while keeping the domain enum untouched. Action gating (e.g.
/// `BudgetDetailView.showPauseResumeItem`) continues to read `lifecycleState`
/// directly — only presentation consumes this type.
enum BudgetInactiveReason: Equatable {
  case preStart(startDate: Date)
  case paused(since: Date)
  case postEnd(endDate: Date)
}

extension BudgetInactiveReason {
  /// Derives the inactive reason (if any) from the lifecycle service result and the budget.
  ///
  /// Returns `nil` when `lifecycleState == .active`. For each inactive case the matching
  /// date payload is sourced from the appropriate place: `pausedSince` from the lifecycle
  /// result; `startDate` / `endDate` from the budget.
  ///
  /// **Defensive nil-date fallback.** If the date payload is unexpectedly `nil` for the
  /// matching lifecycle state (e.g. the budget reaches `.preStart` via clock skew against
  /// `createdAt` while `startDate` is unset, or a future write path produces a `.paused`
  /// state with no recoverable pause date), the helper returns `nil` and the row renders
  /// in its active presentation. The upstream lifecycle service is responsible for
  /// keeping these in sync — see `BudgetLifecycleService.pausedSinceDate(from:now:)` for
  /// the moment-granular contract that backs the `.paused` case.
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
