import Foundation
import SwiftData

// MARK: - Result Type

/// The display-ready output of a `BudgetLifecycleService.result(for:)` call.
///
/// Shape is preserved for view-site compatibility. `lifecycleState` and
/// `effectiveAllocation` from the underlying snapshot are not exposed here;
/// they will be plumbed when the new lifecycle UI features ship.
struct BudgetLifecycleResult {
  /// `effectiveAllocation − net expenses in current period`. May be negative.
  /// Not adjusted by carry-over (PRD §6.7).
  let remaining: Decimal
  /// Carry-over from completed prior active periods plus the current-period spillover.
  /// Maps to `snapshot.carryOver ?? 0` (defensive: `.specificDates` returns `nil` but
  /// no UI in this migration creates that type, so `?? 0` is never triggered).
  let carryOverAmount: Decimal
  /// Inclusive start of the current budget period.
  let periodStart: Date
  /// Exclusive end of the current budget period (start of the next period).
  let periodEnd: Date
}

// MARK: - BudgetLifecycleService

/// Compatibility adapter between the new `BudgetCalculator.snapshot` algorithm and the
/// existing view sites that consume `BudgetLifecycleResult`.
///
/// `result(for:)` is a pure read — it calls `BudgetCalculator.snapshot`, maps the result,
/// and returns it. No mutations.
///
/// Write-path methods (`applyAllocationEdit`, `resetCarryOver`, `resetBudget`) are the
/// entry points for math-affecting mutations. Each bumps `Budget.lastModified` and calls
/// `context.save()` exactly once.
enum BudgetLifecycleService {
  // MARK: - Read path

  /// Returns display-ready values for `budget`. Pure read — does not mutate the budget
  /// or touch the model context.
  static func result(
    for budget: Budget,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> BudgetLifecycleResult {
    let snapshot = BudgetCalculator.snapshot(
      budget: budget,
      expenses: budget.expenseItems,
      now: now,
      calendar: calendar
    )
    return BudgetLifecycleResult(
      remaining: snapshot.remaining,
      carryOverAmount: snapshot.carryOver ?? 0,
      periodStart: snapshot.effectivePeriodStart,
      periodEnd: snapshot.effectivePeriodEnd
    )
  }

  // MARK: - Write paths

  /// Applies an allocation edit: inserts or mutates the `AllocationChange` row for the
  /// current period, then bumps `Budget.lastModified` and saves.
  ///
  /// Uses the insert-or-mutate convention from algorithm doc §A.6.2: if an existing row
  /// has `effectiveFrom == currentPeriodStart`, mutate it; otherwise insert a new row.
  static func applyAllocationEdit(
    _ budget: Budget,
    newAmount: Decimal,
    context: ModelContext,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) {
    guard let periodRaw = BudgetPeriod(rawValue: budget.period),
          let period = RecurringBudgetPeriod(periodRaw)
    else { return }

    let effectiveStartDate = calendar.startOfDay(for: budget.effectiveStartDate)
    let weekdayRaw = calendar.component(.weekday, from: effectiveStartDate)
    let weekStart = Weekday(rawValue: weekdayRaw) ?? .sunday

    let currentPeriodStart = PeriodCalculator.periodStart(
      containing: now,
      period: period,
      weekStart: weekStart,
      biweeklyAnchor: effectiveStartDate,
      calendar: calendar
    )

    if let existing = budget.allocationChanges.first(where: { $0.effectiveFrom == currentPeriodStart }) {
      existing.amount = newAmount
      existing.lastModified = now
    } else {
      let change = AllocationChange(effectiveFrom: currentPeriodStart, amount: newAmount, lastModified: now)
      change.budget = budget
      context.insert(change)
    }

    budget.lastModified = now
    try? context.save()
  }

  /// Resets carry-over to zero from `now` forward by writing `Budget.lastResetDate`.
  ///
  /// The walker honors `lastResetDate` by excluding periods whose end is at or before
  /// this timestamp — no `carryOverAmount` field to zero.
  static func resetCarryOver(
    _ budget: Budget,
    context: ModelContext,
    now: Date = Date()
  ) {
    budget.lastResetDate = now
    budget.lastModified = now
    try? context.save()
  }

  /// Deletes all expenses for `budget`, sets `Budget.lastResetDate = now`, and saves.
  /// Preserves `AllocationChange` and `LifecycleEvent` rows.
  static func resetBudget(
    _ budget: Budget,
    context: ModelContext,
    now: Date = Date()
  ) {
    for expense in Array(budget.expenseItems) {
      context.delete(expense)
    }
    budget.lastResetDate = now
    budget.lastModified = now
    try? context.save()
  }
}
