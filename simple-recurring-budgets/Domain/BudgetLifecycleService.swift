import Foundation
import SwiftData

// MARK: - Result Type

/// Display-ready output of `BudgetLifecycleService.result(for:)`.
///
/// `BudgetSnapshot.effectiveAllocation` is deliberately not exposed: view surfaces read
/// `Budget.currentAllocation`, which `applyAllocationEdit` keeps equal to the current period's in-effect
/// allocation (the F-7.05 / F-7.07 date-input UI relies on this). Plumb it only if a surface needs the
/// period-accurate value for a non-current period.
struct BudgetLifecycleResult: Equatable {
  /// `effectiveAllocation − net expenses in current period`; may be negative. Not adjusted by carry-over (PRD §6.7).
  let remaining: Decimal
  /// Carry-over from completed prior active periods plus current-period spillover: `snapshot.carryOver ?? 0`.
  /// The `?? 0` flattens the `nil` returned for `.specificDates` budgets (hit on every such read); it is never
  /// rendered because per F-2.08 both surfaces hide the carry-over chip for that type
  /// (`isCarryOverEnabled && !isSpecificDates` into `StatusChipRow`).
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

/// Adapter between `BudgetCalculator.snapshot` and the view sites that consume `BudgetLifecycleResult`.
///
/// `result(for:)` is a pure read. The write paths (`applyAllocationEdit`, `resetCarryOver`, `resetBudget`)
/// are the entry points for math-affecting mutations; each bumps `Budget.lastModified` and calls
/// `context.save()` exactly once.
enum BudgetLifecycleService {
  // MARK: - Read path

  /// Display-ready values for `budget`. Pure read. `weekStart` is the global week grid (callers pass
  /// `AppSettings.weekStartDay`; no default so the call site must choose); the service stays settings-free.
  static func result(
    for budget: Budget,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent,
    weekStart: Weekday
  ) -> BudgetLifecycleResult {
    let snapshot = BudgetCalculator.snapshot(
      budget: budget,
      expenses: budget.expenseItems,
      now: now,
      calendar: calendar,
      weekStart: weekStart
    )
    let pausedSince: Date? = snapshot.lifecycleState == .paused
      ? Self.pausedSinceDate(from: budget.lifecycleEvents, now: now)
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

  /// Returns the `effectiveDate` of the most recent `.pause` event with `effectiveDate < now` that is not
  /// followed by a later `.resume` also `< now`; `nil` if none.
  ///
  /// **Moment-granular contract.** The `< now` filter mirrors `isPausedAtMoment(now:)` in
  /// `LifecycleClassification.swift`, which drives the `.paused` state. Without it the two disagree: with
  /// `pause(D1)`, `resume(D2)` and `D1 < now < D2`, `isPausedAtMoment` is true (future resume ignored) but an
  /// unfiltered walker would clear `latestPauseDate` on the future resume, yielding
  /// `.paused && pausedSince == nil`.
  private static func pausedSinceDate(from events: [LifecycleEvent], now: Date) -> Date? {
    let sorted = events.sorted {
      ($0.effectiveDate, $0.lastModified) < ($1.effectiveDate, $1.lastModified)
    }
    var latestPauseDate: Date?
    for event in sorted {
      if event.effectiveDate >= now {
        break
      }
      switch event.kind {
      case .pause: latestPauseDate = event.effectiveDate
      case .resume: latestPauseDate = nil
      }
    }
    return latestPauseDate
  }

  // MARK: - Write paths

  /// Applies an allocation edit: inserts or mutates the `AllocationChange` row for the current period, bumps
  /// `Budget.lastModified`, and saves. Insert-or-mutate: an existing row at the lookup key is mutated,
  /// otherwise a new row is inserted (key explained inline).
  static func applyAllocationEdit(
    _ budget: Budget,
    newAmount: Decimal,
    context: ModelContext,
    analytics: (any AnalyticsClient)? = nil,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent,
    weekStart: Weekday
  ) throws {
    guard let periodRaw = BudgetPeriod(rawValue: budget.period) else { return }
    // Specific Dates: latest-wins whole-window overwrite (F-2.08). Exactly one AllocationChange row exists for the
    // window; mutate it in place (no audit trail; the prior figure isn't retrievable), per F-2.08. The single-row invariant
    // is enforced at create (saveNew) and edit (here); asserts in debug if it drifts (e.g. a future feature adds
    // multi-row history without updating this branch).
    if periodRaw == .specificDates {
      assert(
        budget.allocationChanges.count == 1,
        "applyAllocationEdit: specificDates expects exactly 1 AllocationChange row, got \(budget.allocationChanges.count) — see F-2.08"
      )
      guard let mostRecent = budget.mostRecentAllocationChange, mostRecent.amount != newAmount else { return } // no-op when unchanged
      mostRecent.amount = newAmount
      mostRecent.lastModified = now
      budget.lastModified = now
      try context.saveChanges(operation: .lifecycleAllocationEdit, analytics: analytics)
      return
    }
    guard let period = RecurringBudgetPeriod(periodRaw) else { return }

    let effectiveStartDate = calendar.startOfDay(for: budget.effectiveStartDate)

    let currentPeriodStart = PeriodCalculator.periodStart(
      containing: now,
      period: period,
      weekStart: weekStart,
      biweeklyAnchor: effectiveStartDate,
      calendar: calendar
    )

    // Key on the same instant the snapshot's live read uses, `allocationInEffect(at: max(currentPeriodStart,
    // effectiveStartDate))`, so the write, the live read, and the walker's closed-period lookup (grid boundary
    // with earliest-row fallback) agree. For grid-aligned budgets that equals `currentPeriodStart` (plain
    // insert-or-mutate); for a first period starting mid-grid (monthly created mid-month, weekly off the global
    // week grid) the edit mutates the governing row instead of inserting one the live read would shadow.
    let editKey = max(currentPeriodStart, effectiveStartDate)
    let governingRow = budget.allocationChanges
      .filter { $0.effectiveFrom <= editKey }
      .max { lhs, rhs in
        if lhs.effectiveFrom != rhs.effectiveFrom {
          return lhs.effectiveFrom < rhs.effectiveFrom
        }
        return lhs.lastModified < rhs.lastModified
      }
    if let governingRow, governingRow.effectiveFrom >= currentPeriodStart {
      governingRow.amount = newAmount
      governingRow.lastModified = now
    } else {
      let change = AllocationChange(effectiveFrom: editKey, amount: newAmount, lastModified: now)
      change.budget = budget
      context.insert(change)
    }

    budget.lastModified = now
    try context.saveChanges(operation: .lifecycleAllocationEdit, analytics: analytics)
  }

  /// Resets carry-over to zero from `now` forward by writing `Budget.lastResetDate`. The walker excludes
  /// periods ending at or before it; there is no `carryOverAmount` field to zero.
  static func resetCarryOver(
    _ budget: Budget,
    context: ModelContext,
    analytics: (any AnalyticsClient)? = nil,
    now: Date = Date()
  ) throws {
    // The algorithm ignores `lastResetDate` for specificDates (the F-2.08 UI hides Reset Carry-Over), so a call
    // here would have no effect: assert in debug to surface the UI bug, no-op in release.
    assert(
      budget.periodEnum != .specificDates,
      "resetCarryOver: not supported for specificDates — see F-2.08"
    )
    budget.lastResetDate = now
    budget.lastModified = now
    try context.saveChanges(operation: .lifecycleResetCarryOver, analytics: analytics)
  }

  /// Deletes all expenses for `budget`, sets `Budget.lastResetDate = now`, and saves. Preserves
  /// `AllocationChange` and prior `LifecycleEvent` rows.
  ///
  /// If the budget is `.paused`, also inserts a `.resume` `LifecycleEvent` at `now` so the post-reset state is
  /// `.active`, not paused-but-empty. Does NOT call `resumeBudget(...)`: it saves internally, which would
  /// break the single-save atomicity. The inline insert is safe because `.paused` implies a recurring budget
  /// (Specific Dates aren't pausable) that isn't `.postEnd` (terminal).
  static func resetBudget(
    _ budget: Budget,
    context: ModelContext,
    analytics: (any AnalyticsClient)? = nil,
    now: Date = Date(),
    weekStart: Weekday
  ) throws {
    for expense in Array(budget.expenseItems) {
      context.delete(expense)
    }
    budget.lastResetDate = now
    budget.lastModified = now
    let snapshot = BudgetCalculator.snapshot(
      budget: budget,
      expenses: budget.expenseItems,
      now: now,
      calendar: .autoupdatingCurrent,
      weekStart: weekStart
    )
    if snapshot.lifecycleState == .paused {
      let event = LifecycleEvent(kind: .resume, effectiveDate: now)
      event.budget = budget
      context.insert(event)
    }
    try context.saveChanges(operation: .lifecycleResetBudget, analytics: analytics)
  }

  // MARK: - Pause / Resume (F-7.06)

  /// Pauses `budget` by inserting a `.pause` `LifecycleEvent`. Returns `false` without mutation when the period
  /// is `.specificDates` (not pausable per F-2.08), the state is already `.paused` (no redundant write), or the state is
  /// `.postEnd` (terminal).
  ///
  /// The effective date is `now` clamped into `[startDate, endDate]`, so pausing before `startDate` records the
  /// event at `startDate`.
  @discardableResult
  static func pauseBudget(
    _ budget: Budget,
    context: ModelContext,
    analytics: (any AnalyticsClient)? = nil,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent,
    weekStart: Weekday
  ) throws -> Bool {
    guard budget.periodEnum != .specificDates else { return false }
    let snapshot = BudgetCalculator.snapshot(
      budget: budget,
      expenses: budget.expenseItems,
      now: now,
      calendar: calendar,
      weekStart: weekStart
    )
    guard snapshot.lifecycleState != .paused, snapshot.lifecycleState != .postEnd else { return false }

    let effectiveDate = clamp(now, lower: budget.startDate, upper: budget.endDate)
    let event = LifecycleEvent(kind: .pause, effectiveDate: effectiveDate)
    event.budget = budget
    context.insert(event)
    budget.lastModified = now
    try context.saveChanges(operation: .lifecyclePause, analytics: analytics)
    return true
  }

  /// Resumes `budget` by inserting a `.resume` `LifecycleEvent`. Returns `false` without mutation when the
  /// period is `.specificDates`, the state is `.active`/`.preStart` (no redundant write), or `.postEnd`
  /// (terminal).
  @discardableResult
  static func resumeBudget(
    _ budget: Budget,
    context: ModelContext,
    analytics: (any AnalyticsClient)? = nil,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent,
    weekStart: Weekday
  ) throws -> Bool {
    guard budget.periodEnum != .specificDates else { return false }
    let snapshot = BudgetCalculator.snapshot(
      budget: budget,
      expenses: budget.expenseItems,
      now: now,
      calendar: calendar,
      weekStart: weekStart
    )
    guard snapshot.lifecycleState == .paused else { return false }

    let event = LifecycleEvent(kind: .resume, effectiveDate: now)
    event.budget = budget
    context.insert(event)
    budget.lastModified = now
    try context.saveChanges(operation: .lifecycleResume, analytics: analytics)
    return true
  }

  // MARK: - Private helpers

  private static func clamp(_ date: Date, lower: Date?, upper: Date?) -> Date {
    var result = date
    if let lo = lower, result < lo {
      result = lo
    }
    if let hi = upper, result > hi {
      result = hi
    }
    return result
  }
}
