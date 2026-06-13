import Foundation
import SwiftData

// MARK: - Result Type

/// The display-ready output of a `BudgetLifecycleService.result(for:)` call.
///
/// `effectiveAllocation` from `BudgetSnapshot` is intentionally not exposed here —
/// the F-7.05 / F-7.07 date-input UI shipped without needing it (view surfaces read
/// `Budget.currentAllocation`, which `applyAllocationEdit` keeps equal to the
/// current period's in-effect allocation). Plumb it only if a surface ever needs
/// the period-accurate value for a non-current period.
struct BudgetLifecycleResult: Equatable {
  /// `effectiveAllocation − net expenses in current period`. May be negative.
  /// Not adjusted by carry-over (PRD §6.7).
  let remaining: Decimal
  /// Carry-over from completed prior active periods plus the current-period spillover.
  /// Maps to `snapshot.carryOver ?? 0`. The `?? 0` flattens the `nil` that
  /// `BudgetCalculator.snapshot` returns for `.specificDates` budgets and is exercised
  /// on every specificDates read. The flattened `0` is never rendered: per F-2.08 both
  /// surfaces hide the carry-over chip for that type by passing
  /// `isCarryOverEnabled && !isSpecificDates` into `StatusChipRow` — see
  /// `BudgetDetailView.headerRow` and `BudgetRowView`.
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
  ///
  /// `weekStart` is the global week grid (callers pass `AppSettings.weekStartDay`;
  /// no default — the call site must choose). The service itself stays settings-free.
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

  /// Returns the `effectiveDate` of the most recent `.pause` event with
  /// `effectiveDate < now` that is not followed by a later `.resume` event also
  /// with `effectiveDate < now`. Returns `nil` when no such event exists.
  ///
  /// **Moment-granular contract.** The `< now` filter mirrors `isPausedAtMoment(now:)`
  /// in `LifecycleClassification.swift`, which is the classifier that drives the
  /// `.paused` lifecycle state. Without this filter the two classifiers can disagree —
  /// e.g., events `pause(D1)` and `resume(D2)` with `D1 < now < D2` would give
  /// `isPausedAtMoment == true` (the future resume is ignored) but the unfiltered
  /// walker would clear `latestPauseDate` to `nil` when it processed the future
  /// resume. That mismatch produced `lifecycleState == .paused && pausedSince == nil`,
  /// which broke any view-layer code that expected the two to be consistent.
  private static func pausedSinceDate(from events: [LifecycleEvent], now: Date) -> Date? {
    let sorted = events.sorted {
      ($0.effectiveDate, $0.lastModified) < ($1.effectiveDate, $1.lastModified)
    }
    var latestPauseDate: Date?
    for event in sorted {
      if event.effectiveDate >= now { break }
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
    analytics: (any AnalyticsClient)? = nil,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent,
    weekStart: Weekday
  ) throws {
    guard let periodRaw = BudgetPeriod(rawValue: budget.period) else { return }
    // Specific Dates: latest-wins whole-window overwrite (F-2.08). Exactly one
    // AllocationChange row exists for the entire window; mutate it in place rather
    // than inserting a new row. No audit trail — the prior figure is not retrievable
    // per F-2.08. The count invariant is enforced at create (saveNew) and edit
    // (this method); trip in debug if it ever drifts (e.g., a future feature
    // introduces multi-row history for specificDates without updating this branch).
    if periodRaw == .specificDates {
      assert(
        budget.allocationChanges.count == 1,
        "applyAllocationEdit: specificDates expects exactly 1 AllocationChange row, got \(budget.allocationChanges.count) — see F-2.08"
      )
      guard let mostRecent = budget.mostRecentAllocationChange else { return }
      guard mostRecent.amount != newAmount else { return } // no-op when unchanged
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

    // The edit keys on the same instant the snapshot's live read uses —
    // `allocationInEffect(at: max(currentPeriodStart, effectiveStartDate))` — so the
    // write, the live read, and the walker's closed-period lookup (grid boundary with
    // earliest-row fallback) always agree. For grid-aligned budgets `key ==
    // currentPeriodStart` and this is the original insert-or-mutate convention; for a
    // first period that starts mid-grid (monthly created mid-month, weekly whose
    // startDate is off the global week grid), the edit mutates the row governing the
    // period instead of inserting a row the live read would shadow (issue #247).
    let editKey = max(currentPeriodStart, effectiveStartDate)
    let governingRow = budget.allocationChanges
      .filter { $0.effectiveFrom <= editKey }
      .max { lhs, rhs in
        if lhs.effectiveFrom != rhs.effectiveFrom { return lhs.effectiveFrom < rhs.effectiveFrom }
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

  /// Resets carry-over to zero from `now` forward by writing `Budget.lastResetDate`.
  ///
  /// The walker honors `lastResetDate` by excluding periods whose end is at or before
  /// this timestamp — no `carryOverAmount` field to zero.
  static func resetCarryOver(
    _ budget: Budget,
    context: ModelContext,
    analytics: (any AnalyticsClient)? = nil,
    now: Date = Date()
  ) throws {
    // Reset Carry-Over is hidden in F-2.08 specificDates UI and the algorithm
    // ignores `lastResetDate` for that branch. Calling this on a specificDates
    // budget would write `lastResetDate` with no observable effect — trip in
    // debug to surface the UI bug, no-op in release.
    assert(
      budget.periodEnum != .specificDates,
      "resetCarryOver: not supported for specificDates — see F-2.08"
    )
    budget.lastResetDate = now
    budget.lastModified = now
    try context.saveChanges(operation: .lifecycleResetCarryOver, analytics: analytics)
  }

  /// Deletes all expenses for `budget`, sets `Budget.lastResetDate = now`, and saves.
  /// Preserves `AllocationChange` and prior `LifecycleEvent` rows.
  ///
  /// If `budget.lifecycleState == .paused` at reset time, also inserts a `.resume`
  /// `LifecycleEvent` with `effectiveDate == now` into the same context, so the
  /// post-reset state is `.active` and the user is not left in a paused-but-empty
  /// limbo. Does NOT call `resumeBudget(...)` — that method saves internally,
  /// which would break the single-save atomicity guarantee. The inline insert is
  /// safe because reaching `.paused` implies the budget is recurring (Specific
  /// Dates budgets are not pausable per F-2.08) and not `.postEnd` (a terminal
  /// budget cannot have `.paused` as its current state).
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
    if let lo = lower, result < lo { result = lo }
    if let hi = upper, result > hi { result = hi }
    return result
  }
}
