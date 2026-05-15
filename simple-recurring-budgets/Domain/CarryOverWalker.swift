import Foundation

/// Returns the cumulative carry-over from every completed active period in the walk window.
///
/// Walk window: `[walkWindowStart, currentPeriodStart)`. For each completed period:
/// - active → contributes `allocationInEffect − sum(expenses in period)`.
/// - paused → contributes 0.
///
/// Backdated expenses are automatically folded in on the next call because the walker
/// re-evaluates every period on every read (pure function, no cached state).
func walkCarryOver(
  from walkWindowStart: Date,
  to currentPeriodStart: Date,
  period: RecurringBudgetPeriod,
  weekStart: Weekday,
  biweeklyAnchor: Date,
  allocationChanges: [AllocationChange],
  lifecycleEvents: [LifecycleEvent],
  expenses: [ExpenseItem],
  calendar: Calendar
) -> Decimal {
  let boundaries = PeriodCalculator.periodBoundaries(
    from: walkWindowStart,
    to: currentPeriodStart,
    period: period,
    weekStart: weekStart,
    biweeklyAnchor: biweeklyAnchor,
    calendar: calendar
  )

  var sum: Decimal = 0

  for (i, boundaryStart) in boundaries.enumerated() {
    let nextBoundary: Date = if i + 1 < boundaries.count {
      boundaries[i + 1]
    } else {
      PeriodCalculator.periodEnd(
        containing: boundaryStart,
        period: period,
        weekStart: weekStart,
        biweeklyAnchor: biweeklyAnchor,
        calendar: calendar
      )
    }

    // Only process periods that have fully completed.
    guard nextBoundary <= currentPeriodStart else { break }

    // Paused periods contribute 0.
    guard isActive(
      periodStart: boundaryStart,
      periodEnd: nextBoundary,
      lifecycleEvents: lifecycleEvents
    ) else { continue }

    let allocation = allocationInEffect(at: boundaryStart, history: allocationChanges)
    let periodExpenses = expenses.filter { $0.date >= boundaryStart && $0.date < nextBoundary }
    let contribution = allocation - periodExpenses.reduce(Decimal(0)) { $0 + $1.amount }
    sum += contribution
  }

  return sum
}
