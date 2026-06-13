import Foundation

/// Pure date-math service for computing budget period boundaries.
///
/// All methods accept `RecurringBudgetPeriod` — `.specificDates` cannot reach this service
/// at compile time. `weekStart` is the global week grid (production callers thread
/// `AppSettings.weekStartDay` down through `BudgetCalculator.snapshot`); it is consumed
/// only by the `.weekly` branch. `biweeklyAnchor` is the budget's own `startDate` — the
/// 14-day cycle's phase comes from that date and never from `weekStart` (#240).
/// Production callers pass `Calendar.autoupdatingCurrent`; tests inject a fixed-UTC
/// calendar.
enum PeriodCalculator {
  // MARK: - Period Start

  /// Returns the start date of the budget period containing `date`.
  ///
  /// - Parameters:
  ///   - date: The reference date.
  ///   - period: The budget's repeating period (recurring types only).
  ///   - weekStart: The global week-start day (`AppSettings.weekStartDay`); weekly only.
  ///   - biweeklyAnchor: The cycle anchor for biweekly periods (ignored for others).
  ///   - calendar: The calendar to use for all date arithmetic.
  static func periodStart(
    containing date: Date,
    period: RecurringBudgetPeriod,
    weekStart: Weekday,
    biweeklyAnchor: Date,
    calendar: Calendar
  ) -> Date {
    switch period {
    case .daily:
      return calendar.startOfDay(for: date)

    case .weekly:
      let dayStart = calendar.startOfDay(for: date)
      let weekdayOfDate = calendar.component(.weekday, from: dayStart)
      let daysBack = (weekdayOfDate - weekStart.rawValue + 7) % 7
      return calendar.date(byAdding: .day, value: -daysBack, to: dayStart)!

    case .biweekly:
      let dayStart = calendar.startOfDay(for: date)
      let anchorStart = calendar.startOfDay(for: biweeklyAnchor)
      let daysDiff = calendar.dateComponents([.day], from: anchorStart, to: dayStart).day ?? 0
      let periodsElapsed = floorDiv(daysDiff, 14)
      return calendar.date(byAdding: .day, value: periodsElapsed * 14, to: anchorStart)!

    case .monthly:
      var comps = calendar.dateComponents([.year, .month], from: date)
      comps.day = 1
      comps.hour = 0
      comps.minute = 0
      comps.second = 0
      return calendar.date(from: comps)!
    }
  }

  // MARK: - Period End

  /// Returns the start of the period immediately following the one containing `date`.
  static func periodEnd(
    containing date: Date,
    period: RecurringBudgetPeriod,
    weekStart: Weekday,
    biweeklyAnchor: Date,
    calendar: Calendar
  ) -> Date {
    let start = periodStart(
      containing: date,
      period: period,
      weekStart: weekStart,
      biweeklyAnchor: biweeklyAnchor,
      calendar: calendar
    )
    switch period {
    case .daily: return calendar.date(byAdding: .day, value: 1, to: start)!
    case .weekly: return calendar.date(byAdding: .day, value: 7, to: start)!
    case .biweekly: return calendar.date(byAdding: .day, value: 14, to: start)!
    case .monthly: return calendar.date(byAdding: .month, value: 1, to: start)!
    }
  }

  // MARK: - Period Boundary Enumeration

  /// Returns all period-start dates in `[from, to)`.
  ///
  /// Begins at `periodStart(containing: from, ...)` and advances one period at a time
  /// until the next boundary would equal or exceed `to`. Returns `[]` when `from >= to`.
  static func periodBoundaries(
    from start: Date,
    to end: Date,
    period: RecurringBudgetPeriod,
    weekStart: Weekday,
    biweeklyAnchor: Date,
    calendar: Calendar
  ) -> [Date] {
    var boundaries: [Date] = []
    var current = periodStart(
      containing: start,
      period: period,
      weekStart: weekStart,
      biweeklyAnchor: biweeklyAnchor,
      calendar: calendar
    )
    while current < end {
      boundaries.append(current)
      current = periodEnd(
        containing: current,
        period: period,
        weekStart: weekStart,
        biweeklyAnchor: biweeklyAnchor,
        calendar: calendar
      )
    }
    return boundaries
  }

  // MARK: - Private Helpers

  /// Floor division: largest integer q such that q * d <= n (for positive d).
  private static func floorDiv(_ n: Int, _ d: Int) -> Int {
    let q = n / d
    return n % d < 0 ? q - 1 : q
  }
}
