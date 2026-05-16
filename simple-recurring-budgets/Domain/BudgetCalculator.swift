import Foundation

/// Financial math service — pure, stateless, no SwiftData or SwiftUI dependencies.
///
/// The single entry point is `snapshot(budget:expenses:now:calendar:)`. It reads
/// `Budget` and `[ExpenseItem]` and returns an immutable `BudgetSnapshot`; it never
/// mutates any model or saves to a `ModelContext`. Production callers pass
/// `Calendar.autoupdatingCurrent`; tests inject a fixed-UTC calendar.
enum BudgetCalculator {
  // MARK: - Main entry point

  static func snapshot(
    budget: Budget,
    expenses: [ExpenseItem],
    now: Date,
    calendar: Calendar
  ) -> BudgetSnapshot {
    let effectiveStartDate = calendar.startOfDay(for: budget.effectiveStartDate)
    let effectiveEndInclusive: Date? = budget.endDate.map { calendar.startOfDay(for: $0) }
    let effectiveEndExclusive: Date = effectiveEndInclusive.map { inclusive in
      calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: inclusive)!)
    } ?? .distantFuture

    // Sort history collections once at the entry point — both `allocationInEffect` and
    // `isActive` require pre-sorted input (see their contracts). This avoids re-sorting
    // inside the walker hot loop.
    let sortedAllocationChanges = budget.allocationChanges.sorted { lhs, rhs in
      if lhs.effectiveFrom != rhs.effectiveFrom { return lhs.effectiveFrom < rhs.effectiveFrom }
      return lhs.lastModified < rhs.lastModified
    }
    let sortedLifecycleEvents = budget.lifecycleEvents.sorted { lhs, rhs in
      if lhs.effectiveDate != rhs.effectiveDate { return lhs.effectiveDate < rhs.effectiveDate }
      return lhs.lastModified < rhs.lastModified
    }

    // Pre-start short-circuit
    if now < effectiveStartDate {
      let alloc = allocationInEffect(at: effectiveStartDate, sortedHistory: sortedAllocationChanges)
      let periodRawForPreStart = BudgetPeriod(rawValue: budget.period) ?? .daily
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

    // Branch on period type
    let periodRaw = BudgetPeriod(rawValue: budget.period) ?? .daily
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
      // Unreachable today: `.specificDates` is the only non-recurring case and is handled
      // above. Trip in debug if a future non-recurring case slips past that branch; in
      // release, return a safe zero snapshot so the UI degrades gracefully rather than
      // crashes on a hot read path.
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
      period: period,
      effectiveStartDate: effectiveStartDate,
      effectiveEndInclusive: effectiveEndInclusive,
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
    period: RecurringBudgetPeriod,
    effectiveStartDate: Date,
    effectiveEndInclusive: Date?,
    effectiveEndExclusive: Date,
    sortedAllocationChanges: [AllocationChange],
    sortedLifecycleEvents: [LifecycleEvent]
  ) -> BudgetSnapshot {
    // Clamp `now` to `effectiveEndInclusive` so post-end snapshots reflect the *final*
    // period (the one containing `endDate`) rather than whatever period calendar-now
    // would fall into. Without this clamp, a daily budget that ended Apr 10 viewed on
    // Apr 20 would compute its "current" period as Apr 20 — there'd be no allocation
    // history covering that date and the math would be wrong. The lifecycle classification
    // below still uses raw `now` to decide postEnd vs active — only the period math is clamped.
    let effectiveNow = effectiveEndInclusive.map { min(now, $0) } ?? now

    let weekdayRaw = calendar.component(.weekday, from: effectiveStartDate)
    let weekStart = Weekday(rawValue: weekdayRaw) ?? .sunday
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

    // Use the clamped `effectivePeriodEnd` (not raw `currentPeriodEnd`) so that
    // lifecycle events past `endDate` cannot flip the pause classification for a
    // postEnd budget's final period.
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

    let lifecycleState: BudgetLifecycleState = if budget.endDate != nil, now >= effectiveEndExclusive {
      .postEnd
    } else if isCurrentPaused {
      .paused
    } else {
      .active
    }

    let spillover = currentPeriodSpillover(
      remaining: remaining,
      effectiveAllocation: effectiveAllocation,
      lifecycleState: lifecycleState
    )

    return BudgetSnapshot(
      lifecycleState: lifecycleState,
      effectiveAllocation: effectiveAllocation,
      remaining: remaining,
      carryOver: walkerSum + spillover,
      effectivePeriodStart: effectivePeriodStart,
      effectivePeriodEnd: effectivePeriodEnd
    )
  }

  // MARK: - Specific Dates branch (§A.4.2)

  /// Specific Dates is a single-window, no-recurrence budget type (F-2.08).
  ///
  /// **Intentionally ignored fields:** `Budget.lastResetDate`, `Budget.lifecycleEvents`,
  /// and `Budget.isCarryOverEnabled` are NOT consulted here. Per F-2.08, the UI hides
  /// Reset Carry-Over, the carry-over toggle, and Pause/Resume for this period type;
  /// the algorithm correspondingly ignores those signals if they ever land on a
  /// specificDates row (direct CloudKit write, UI bug, etc.). Allocation uses
  /// latest-wins (most-recent `AllocationChange` by `(effectiveFrom, lastModified)`)
  /// rather than the period-history walk used by recurring budgets.
  ///
  /// Future agents wiring the F-2.08 UI: do **not** thread `lastResetDate` or
  /// `lifecycleEvents` through this branch — re-read F-2.08 first.
  private static func specificDatesBranch(
    budget: Budget,
    expenses: [ExpenseItem],
    now: Date,
    effectiveStartDate: Date,
    effectiveEndExclusive: Date
  ) -> BudgetSnapshot {
    let effectiveAllocation = budget.allocationChanges.max { lhs, rhs in
      if lhs.effectiveFrom != rhs.effectiveFrom { return lhs.effectiveFrom < rhs.effectiveFrom }
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
