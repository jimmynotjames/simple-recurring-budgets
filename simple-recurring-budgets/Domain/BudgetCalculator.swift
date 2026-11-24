import Foundation

/// Financial math service: pure and stateless, no SwiftData or SwiftUI dependencies.
///
/// Single entry point `snapshot(budget:expenses:now:calendar:weekStart:)` reads `Budget` and `[ExpenseItem]`
/// and returns an immutable `BudgetSnapshot`; it never mutates models or saves. Production passes
/// `Calendar.autoupdatingCurrent`; tests inject a fixed-UTC calendar.
///
/// `weekStart` is the **global** week grid (production passes `AppSettings.weekStartDay`; deliberately no
/// default so every call site chooses). It governs only `.weekly` budgets: all weekly budgets share the grid
/// (as all monthly budgets share the calendar-month grid), and a mid-grid `startDate` just clips the first
/// period (full allocation, no proration). Biweekly cycles stay anchored to the budget's own `startDate`
/// (a weekday can't determine which of two alternating weeks a 14-day cycle restarts in), so `weekStart`
/// never affects them (see budget-math spec).
enum BudgetCalculator {
  // MARK: - Main entry point

  static func snapshot(
    budget: Budget,
    expenses: [ExpenseItem],
    now: Date,
    calendar: Calendar,
    weekStart: Weekday
  ) -> BudgetSnapshot {
    let effectiveStartDate = calendar.startOfDay(for: budget.effectiveStartDate)
    let effectiveEndInclusive: Date? = budget.endDate.map { calendar.startOfDay(for: $0) }
    let effectiveEndExclusive: Date = effectiveEndInclusive.map { inclusive in
      calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: inclusive)!)
    } ?? .distantFuture

    // Sort once here: `allocationInEffect` and `isActive` require sorted input, and this avoids re-sorting in the walker loop.
    let sortedAllocationChanges = budget.allocationChanges.sorted { lhs, rhs in
      if lhs.effectiveFrom != rhs.effectiveFrom {
        return lhs.effectiveFrom < rhs.effectiveFrom
      }
      return lhs.lastModified < rhs.lastModified
    }
    let sortedLifecycleEvents = budget.lifecycleEvents.sorted { lhs, rhs in
      if lhs.effectiveDate != rhs.effectiveDate {
        return lhs.effectiveDate < rhs.effectiveDate
      }
      return lhs.lastModified < rhs.lastModified
    }

    // Pre-start short-circuit
    if now < effectiveStartDate {
      let alloc = allocationInEffect(at: effectiveStartDate, sortedHistory: sortedAllocationChanges)
      let periodRawForPreStart = budget.periodEnum
      let preStartCarryOver: Decimal? = periodRawForPreStart == .specificDates ? nil : 0
      return BudgetSnapshot(
        lifecycleState: .preStart,
        effectiveAllocation: alloc,
        remaining: 0,
        carryOver: preStartCarryOver,
        effectivePeriodStart: effectiveStartDate,
        effectivePeriodEnd: effectiveStartDate
      )
    }

    let periodRaw = budget.periodEnum
    if periodRaw == .specificDates {
      return specificDatesBranch(
        budget: budget,
        expenses: expenses,
        now: now,
        effectiveStartDate: effectiveStartDate,
        effectiveEndExclusive: effectiveEndExclusive
      )
    }

    guard let period = RecurringBudgetPeriod(periodRaw) else {
      // Unreachable: `.specificDates` is the only non-recurring case and is handled above. Asserts in debug if a
      // new non-recurring case slips through; release returns a safe zero snapshot rather than crash on a hot read path.
      assertionFailure("snapshot: non-recurring period reached recurring branch — invariant broken")
      return BudgetSnapshot(
        lifecycleState: .active,
        effectiveAllocation: 0,
        remaining: 0,
        carryOver: 0,
        effectivePeriodStart: effectiveStartDate,
        effectivePeriodEnd: effectiveStartDate
      )
    }

    return recurringBranch(
      budget: budget,
      expenses: expenses,
      now: now,
      calendar: calendar,
      weekStart: weekStart,
      period: period,
      effectiveStartDate: effectiveStartDate,
      effectiveEndExclusive: effectiveEndExclusive,
      sortedAllocationChanges: sortedAllocationChanges,
      sortedLifecycleEvents: sortedLifecycleEvents
    )
  }

  // MARK: - Recurring branch

  private static func recurringBranch(
    budget: Budget,
    expenses: [ExpenseItem],
    now: Date,
    calendar: Calendar,
    weekStart: Weekday,
    period: RecurringBudgetPeriod,
    effectiveStartDate: Date,
    effectiveEndExclusive: Date,
    sortedAllocationChanges: [AllocationChange],
    sortedLifecycleEvents: [LifecycleEvent]
  ) -> BudgetSnapshot {
    // Re-derived locally (not passed in) to keep the parameter list at the lint cap.
    let effectiveEndInclusive: Date? = budget.endDate.map { calendar.startOfDay(for: $0) }
    // Clamp `now` to `effectiveEndInclusive` so post-end snapshots reflect the *final* period (containing
    // `endDate`), not the period calendar-now falls in. Unclamped, a daily budget ended Apr 10 and viewed Apr 20
    // would compute Apr 20 as current, with no allocation history covering it. Lifecycle classification below
    // still uses raw `now` for postEnd vs active; only the period math is clamped.
    let effectiveNow = effectiveEndInclusive.map { min(now, $0) } ?? now

    // `weekStart` (global `AppSettings.weekStartDay`) feeds only the weekly grid; biweekly phase comes from the budget's start date, not a weekday.
    let biweeklyAnchor = effectiveStartDate

    let currentPeriodStart = PeriodCalculator.periodStart(
      containing: effectiveNow, period: period, weekStart: weekStart,
      biweeklyAnchor: biweeklyAnchor, calendar: calendar
    )
    let currentPeriodEnd = PeriodCalculator.periodEnd(
      containing: effectiveNow, period: period, weekStart: weekStart,
      biweeklyAnchor: biweeklyAnchor, calendar: calendar
    )

    let effectivePeriodStart = max(currentPeriodStart, effectiveStartDate)
    let effectivePeriodEnd = min(currentPeriodEnd, effectiveEndExclusive)

    // Use the clamped `effectivePeriodEnd` (not raw `currentPeriodEnd`) so lifecycle events past `endDate`
    // can't flip the pause classification of a postEnd budget's final period.
    let isCurrentPaused = !isActive(
      periodStart: effectivePeriodStart,
      periodEnd: effectivePeriodEnd,
      sortedLifecycleEvents: sortedLifecycleEvents
    )
    let effectiveAllocation = allocationInEffect(
      at: max(currentPeriodStart, effectiveStartDate),
      sortedHistory: sortedAllocationChanges
    )

    let remaining: Decimal
    if isCurrentPaused {
      remaining = 0
    } else {
      let inPeriod = expenses.filter { $0.date >= effectivePeriodStart && $0.date < effectivePeriodEnd }
      remaining = effectiveAllocation - inPeriod.reduce(Decimal(0)) { $0 + $1.amount }
    }

    let walkWindowStart = max(effectiveStartDate, budget.lastResetDate ?? .distantPast)
    let walkerSum = walkCarryOver(
      from: walkWindowStart, to: currentPeriodStart, period: period,
      weekStart: weekStart, biweeklyAnchor: biweeklyAnchor,
      sortedAllocationChanges: sortedAllocationChanges,
      sortedLifecycleEvents: sortedLifecycleEvents,
      expenses: expenses, calendar: calendar
    )

    // UI classification is moment-granular (flips once a .pause event's effectiveDate is reached); math
    // classification (`isCurrentPaused`) is period-granular: the pause-action period still feeds the walker,
    // and the `remaining = 0` short-circuit applies only to fully-paused periods.
    let uiIsPaused = isPausedAtMoment(now: now, sortedLifecycleEvents: sortedLifecycleEvents)
    let lifecycleState: BudgetLifecycleState = if budget.endDate != nil, now >= effectiveEndExclusive {
      .postEnd
    } else if uiIsPaused {
      .paused
    } else {
      .active
    }

    // Spillover honors `lastResetDate` (budget-math spec, "Reset interaction"): its input excludes pre-reset expenses but still awards the full
    // allocation (the walker's no-proration convention for the reset period), so it equals what the walker
    // contributes when the period closes and committed overflow carries continuously across the boundary
    // (ordinary slack still waits for the close). `remaining` above deliberately keeps all current-period
    // expenses (post-reset rebound).
    // A reset stamped after the budget ended (`lastResetDate >= effectiveEndExclusive`; reachable only in
    // .postEnd since write paths stamp `now`) leaves nothing to spill. Without this carve-out a post-end
    // Reset Budget would fold the rebounded final-period remaining (the full allocation) back into carry-over.
    let spillover: Decimal
    if let lastReset = budget.lastResetDate, lastReset >= effectiveEndExclusive {
      spillover = 0
    } else {
      let spilloverRemaining: Decimal
      if isCurrentPaused {
        spilloverRemaining = 0
      } else {
        let lowerBound = max(effectivePeriodStart, budget.lastResetDate ?? .distantPast)
        let postReset = expenses.filter { $0.date >= lowerBound && $0.date < effectivePeriodEnd }
        spilloverRemaining = effectiveAllocation - postReset.reduce(Decimal(0)) { $0 + $1.amount }
      }
      spillover = currentPeriodSpillover(
        remaining: spilloverRemaining,
        effectiveAllocation: effectiveAllocation,
        lifecycleState: lifecycleState
      )
    }

    return BudgetSnapshot(
      lifecycleState: lifecycleState,
      effectiveAllocation: effectiveAllocation,
      remaining: remaining,
      carryOver: walkerSum + spillover,
      effectivePeriodStart: effectivePeriodStart,
      effectivePeriodEnd: effectivePeriodEnd
    )
  }

  // MARK: - Specific Dates branch

  /// Specific Dates: a single-window, no-recurrence budget type (F-2.08).
  ///
  /// **Intentionally ignored:** `Budget.lastResetDate`, `Budget.lifecycleEvents`, and
  /// `Budget.isCarryOverEnabled`. Per F-2.08, the UI hides Reset Carry-Over, the carry-over toggle, and Pause/Resume for
  /// this type, so the math ignores those signals if they ever land on a specificDates row (direct CloudKit
  /// write, UI bug). Allocation is latest-wins (most recent `AllocationChange` by
  /// `(effectiveFrom, lastModified)`), not the period-history walk recurring budgets use.
  ///
  /// Future agents wiring the F-2.08 UI: do **not** thread `lastResetDate` or `lifecycleEvents` through this
  /// branch (re-read F-2.08 first).
  private static func specificDatesBranch(
    budget: Budget,
    expenses: [ExpenseItem],
    now: Date,
    effectiveStartDate: Date,
    effectiveEndExclusive: Date
  ) -> BudgetSnapshot {
    let effectiveAllocation = budget.allocationChanges.max { lhs, rhs in
      if lhs.effectiveFrom != rhs.effectiveFrom {
        return lhs.effectiveFrom < rhs.effectiveFrom
      }
      return lhs.lastModified < rhs.lastModified
    }?.amount ?? 0

    let windowExpenses = expenses.filter { $0.date >= effectiveStartDate && $0.date < effectiveEndExclusive }
    let remaining = effectiveAllocation - windowExpenses.reduce(Decimal(0)) { $0 + $1.amount }
    let lifecycleState: BudgetLifecycleState = now >= effectiveEndExclusive ? .postEnd : .active

    return BudgetSnapshot(
      lifecycleState: lifecycleState,
      effectiveAllocation: effectiveAllocation,
      remaining: remaining,
      carryOver: nil,
      effectivePeriodStart: effectiveStartDate,
      effectivePeriodEnd: effectiveEndExclusive
    )
  }
}
