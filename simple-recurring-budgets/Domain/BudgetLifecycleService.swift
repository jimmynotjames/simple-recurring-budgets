import Foundation
import SwiftData

// MARK: - Result Type

/// The display-ready output of a `BudgetLifecycleService.result(for:)` call.
///
/// `effectiveAllocation` from `BudgetSnapshot` is intentionally not exposed here — it
/// will be plumbed when the start-date / end-date input UI ships (F-7.05 / F-7.07).
struct BudgetLifecycleResult: Equatable {
  /// `effectiveAllocation − net expenses in current period`. May be negative.
  /// Not adjusted by carry-over (PRD §6.7).
  let remaining: Decimal
  /// Carry-over from completed prior active periods plus the current-period spillover.
  /// Maps to `snapshot.carryOver ?? 0`. The `?? 0` flattens the `nil` that
  /// `BudgetCalculator.snapshot` returns for `.specificDates` budgets — see F-2.08, which
  /// requires the carry-over chip to be **hidden** for that type (the chip-hiding work
  /// lives in `BudgetDetailView` and `BudgetRowView` and ships with the F-2.08 UI). Until
  /// then this fallback is unreachable in normal flow; the F-2.08 work should either
  /// stop calling this entry point for specificDates budgets or replace `BudgetLifecycleResult`
  /// with a sum type that does not flatten `nil`.
  let carryOverAmount: Decimal
  /// Inclusive start of the current budget period.
  let periodStart: Date
  /// Exclusive end of the current budget period (start of the next period).
  let periodEnd: Date
  /// The lifecycle classification at the snapshot instant (F-7.06).
  let lifecycleState: BudgetLifecycleState
  /// When `lifecycleState == .paused`, the `effectiveDate` of the most recent unbalanced
  /// `.pause` `LifecycleEvent`. `nil` when the budget is not currently paused.
  let pausedSince: Date?
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
    let pausedSince: Date? = snapshot.lifecycleState == .paused
      ? Self.pausedSinceDate(from: budget.lifecycleEvents)
      : nil
    return BudgetLifecycleResult(
      remaining: snapshot.remaining,
      carryOverAmount: snapshot.carryOver ?? 0,
      periodStart: snapshot.effectivePeriodStart,
      periodEnd: snapshot.effectivePeriodEnd,
      lifecycleState: snapshot.lifecycleState,
      pausedSince: pausedSince
    )
  }

  /// Returns the `effectiveDate` of the most recent `.pause` event that is not followed by
  /// a later `.resume` event. Returns `nil` when no such event exists.
  private static func pausedSinceDate(from events: [LifecycleEvent]) -> Date? {
    let sorted = events.sorted {
      ($0.effectiveDate, $0.lastModified) < ($1.effectiveDate, $1.lastModified)
    }
    var latestPauseDate: Date?
    for event in sorted {
      switch event.kind {
      case .pause: latestPauseDate = event.effectiveDate
      case .resume: latestPauseDate = nil
      }
    }
    return latestPauseDate
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
    guard let periodRaw = BudgetPeriod(rawValue: budget.period) else { return }
    // Specific Dates uses latest-wins allocation semantics (F-2.08), which is a
    // distinct write path from the recurring-budget insert-or-mutate convention.
    // The F-2.08 UI is not yet wired; trip in debug if anything routes a
    // specificDates budget here so the gap is loud, but no-op in release.
    assert(periodRaw != .specificDates, "applyAllocationEdit: specificDates not supported here yet — see F-2.08")
    guard let period = RecurringBudgetPeriod(periodRaw) else { return }

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
    // Reset Carry-Over is hidden in F-2.08 specificDates UI and the algorithm
    // ignores `lastResetDate` for that branch. Calling this on a specificDates
    // budget would write `lastResetDate` with no observable effect — trip in
    // debug to surface the UI bug, no-op in release.
    assert(
      BudgetPeriod(rawValue: budget.period) != .specificDates,
      "resetCarryOver: not supported for specificDates — see F-2.08"
    )
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

  // MARK: - Pause / Resume (F-7.06)

  /// Pauses `budget` by inserting a `.pause` `LifecycleEvent`.
  ///
  /// Returns `false` without any mutation when:
  /// - the budget's `period` is `.specificDates` (Specific Dates budgets are not pausable).
  /// - the current `lifecycleState` is already `.paused` (no redundant write).
  /// - the current `lifecycleState` is `.postEnd` (terminal — cannot pause or resume).
  ///
  /// The effective date is `now` clamped into `[startDate, endDate]` so that pausing
  /// before `startDate` records the event at `startDate` per reqs §5.5.
  @discardableResult
  static func pauseBudget(
    _ budget: Budget,
    context: ModelContext,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> Bool {
    guard BudgetPeriod(rawValue: budget.period) != .specificDates else { return false }
    let snapshot = BudgetCalculator.snapshot(
      budget: budget,
      expenses: budget.expenseItems,
      now: now,
      calendar: calendar
    )
    guard snapshot.lifecycleState != .paused, snapshot.lifecycleState != .postEnd else { return false }

    let effectiveDate = clamp(now, lower: budget.startDate, upper: budget.endDate)
    let event = LifecycleEvent(kind: .pause, effectiveDate: effectiveDate)
    event.budget = budget
    context.insert(event)
    budget.lastModified = now
    try? context.save()
    return true
  }

  /// Resumes `budget` by inserting a `.resume` `LifecycleEvent`.
  ///
  /// Returns `false` without any mutation when:
  /// - the budget's `period` is `.specificDates`.
  /// - the current `lifecycleState` is `.active` or `.preStart` (no redundant write).
  /// - the current `lifecycleState` is `.postEnd` (`endDate` is terminal — cannot resume).
  @discardableResult
  static func resumeBudget(
    _ budget: Budget,
    context: ModelContext,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> Bool {
    guard BudgetPeriod(rawValue: budget.period) != .specificDates else { return false }
    let snapshot = BudgetCalculator.snapshot(
      budget: budget,
      expenses: budget.expenseItems,
      now: now,
      calendar: calendar
    )
    guard snapshot.lifecycleState == .paused else { return false }

    let event = LifecycleEvent(kind: .resume, effectiveDate: now)
    event.budget = budget
    context.insert(event)
    budget.lastModified = now
    try? context.save()
    return true
  }

  // MARK: - Private helpers

  private static func clamp(_ date: Date, lower: Date?, upper: Date?) -> Date {
    var result = date
    if let lo = lower, result < lo { result = lo }
    if let hi = upper, result > hi { result = hi }
    return result
  }
}
