import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - BudgetInactiveReason.from

/// Tests cover the four `BudgetLifecycleState` cases plus the defensive nil-date
/// branches for `.preStart` / `.paused` / `.postEnd` (where the matching date
/// payload is unexpectedly absent — the helper falls through to `nil`, which the
/// view layer treats as "render as active").
struct BudgetInactiveReasonTests {
  // MARK: - Helpers

  private static func makeLifecycle(
    state: BudgetLifecycleState,
    pausedSince: Date? = nil
  ) -> BudgetLifecycleResult {
    BudgetLifecycleResult(
      remaining: 0,
      carryOverAmount: 0,
      periodStart: Date(),
      periodEnd: Date(),
      lifecycleState: state,
      pausedSince: pausedSince
    )
  }

  // MARK: - Active

  @Test func active_returnsNil() {
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .monthly)
    let lifecycle = Self.makeLifecycle(state: .active)
    #expect(BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget) == nil)
  }

  // MARK: - PreStart

  @Test func preStart_withStartDate_returnsPreStart() {
    let startDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .monthly)
    budget.startDate = startDate
    let lifecycle = Self.makeLifecycle(state: .preStart)
    #expect(BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget) == .preStart(startDate: startDate))
  }

  // MARK: - Paused

  @Test func paused_withPausedSince_returnsPaused() {
    let pausedSince = Date(timeIntervalSinceReferenceDate: 800_500_000)
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .monthly)
    let lifecycle = Self.makeLifecycle(state: .paused, pausedSince: pausedSince)
    #expect(BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget) == .paused(since: pausedSince))
  }

  // MARK: - PostEnd

  @Test func postEnd_withEndDate_returnsPostEnd() {
    let endDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .monthly)
    budget.endDate = endDate
    let lifecycle = Self.makeLifecycle(state: .postEnd)
    #expect(BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget) == .postEnd(endDate: endDate))
  }

  // MARK: - Defensive nil-date fallbacks

  /// `.preStart` with `nil` startDate is unexpected (the calculator only reaches
  /// `.preStart` via clock skew when `startDate` is unset), but the helper must
  /// fail safe — return `nil` so the row renders as active rather than crashing.
  @Test func preStart_withNilStartDate_returnsNil() {
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .monthly)
    budget.startDate = nil
    let lifecycle = Self.makeLifecycle(state: .preStart)
    #expect(BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget) == nil)
  }

  /// `.paused` with `nil` pausedSince should be unreachable after the fix to
  /// `BudgetLifecycleService.pausedSinceDate(from:now:)` (which now filters
  /// future events to stay consistent with `isPausedAtMoment`). The helper
  /// keeps a defensive fallback to `nil` in case a synthetic result ever
  /// produces this combination.
  @Test func paused_withNilPausedSince_returnsNil() {
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .monthly)
    let lifecycle = Self.makeLifecycle(state: .paused, pausedSince: nil)
    #expect(BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget) == nil)
  }

  /// `.postEnd` with `nil` endDate is unreachable via the calculator (which
  /// requires `endDate != nil` to ever return `.postEnd`), but the helper
  /// fails safe to `nil` for defense in depth.
  @Test func postEnd_withNilEndDate_returnsNil() {
    let budget = Budget(name: "Groceries", currencyCode: "USD", period: .monthly)
    budget.endDate = nil
    let lifecycle = Self.makeLifecycle(state: .postEnd)
    #expect(BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget) == nil)
  }
}
