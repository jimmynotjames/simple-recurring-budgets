import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - Shared test calendar

/// Fixed-UTC Gregorian calendar for deterministic date arithmetic.
private let utcCalendar: Calendar = {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  return cal
}()

/// Midnight UTC (or `hour`) on the given day.
private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year
  comps.month = month
  comps.day = day
  comps.hour = hour
  comps.minute = 0
  comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

// MARK: - PeriodCalculator.periodStart

struct PeriodCalculatorPeriodStartTests {
  // MARK: Daily

  @Test func periodStart_daily_stripsTimeToMidnight() {
    let date = utcDate(2026, 4, 15, hour: 14) // 2026-04-15 14:00 UTC
    let result = PeriodCalculator.periodStart(
      containing: date,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: date,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 15))
  }

  @Test func periodStart_daily_atMidnightReturnsSameDate() {
    let date = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodStart(
      containing: date,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: date,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 15))
  }

  // MARK: Weekly

  /// 2026-04-15 is a Wednesday; with Sunday week-start the period began 2026-04-12.
  @Test func periodStart_weekly_sundayWeekStart_returnsCorrectSunday() {
    let wednesday = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodStart(
      containing: wednesday,
      period: .weekly,
      weekStart: .sunday,
      biweeklyAnchor: wednesday,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 12))
  }

  /// With Monday week-start the period began 2026-04-13.
  @Test func periodStart_weekly_mondayWeekStart_returnsCorrectMonday() {
    let wednesday = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodStart(
      containing: wednesday,
      period: .weekly,
      weekStart: .monday,
      biweeklyAnchor: wednesday,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 13))
  }

  /// On the week-start day itself, periodStart returns that date.
  @Test func periodStart_weekly_onWeekStartDay_returnsSameDay() {
    let sunday = utcDate(2026, 4, 12) // confirmed Sunday
    let result = PeriodCalculator.periodStart(
      containing: sunday,
      period: .weekly,
      weekStart: .sunday,
      biweeklyAnchor: sunday,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 12))
  }

  @Test func periodStart_weekly_mondayOnMonday_returnsSameDay() {
    let monday = utcDate(2026, 4, 13) // confirmed Monday
    let result = PeriodCalculator.periodStart(
      containing: monday,
      period: .weekly,
      weekStart: .monday,
      biweeklyAnchor: monday,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 13))
  }

  // MARK: Biweekly

  /// Anchor is Sunday 2026-03-29 (the Sunday on/before a Wed 2026-04-01 creation date).
  /// 2026-04-17 is 19 days out → 1 full cycle elapsed → start = anchor + 14 = 2026-04-12.
  @Test func periodStart_biweekly_correctCycleAlignment() {
    let anchor = utcDate(2026, 3, 29) // Sunday (biweekly anchor, derived from createdAt)
    let testDate = utcDate(2026, 4, 17) // 19 days after anchor → period 1 (14..27 days from anchor)
    let result = PeriodCalculator.periodStart(
      containing: testDate,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 12))
  }

  /// Within the first 14 days, the anchor itself is the period start.
  @Test func periodStart_biweekly_firstPeriodReturnsAnchor() {
    let anchor = utcDate(2026, 3, 29)
    let testDate = utcDate(2026, 4, 5) // 7 days after anchor — still in first 14-day period
    let result = PeriodCalculator.periodStart(
      containing: testDate,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 3, 29))
  }

  /// Dates BEFORE the anchor exercise `floorDiv`'s negative branch: daysDiff −7 gives
  /// floorDiv(−7, 14) = −1 (truncating division would give 0), so the date lands in the cycle
  /// starting anchor − 14, never a phantom cycle at the anchor. Load-bearing for back-dated
  /// snapshots and for keeping biweekly phase anchored to the budget's own startDate.
  @Test func periodStart_biweekly_dateBeforeAnchor_negativePhase() {
    let anchor = utcDate(2026, 4, 12) // Sunday
    let weekBefore = utcDate(2026, 4, 5) // daysDiff = −7 → floorDiv = −1
    let start = PeriodCalculator.periodStart(
      containing: weekBefore,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: utcCalendar
    )
    #expect(start == utcDate(2026, 3, 29)) // anchor − 14
    let end = PeriodCalculator.periodEnd(
      containing: weekBefore,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: utcCalendar
    )
    #expect(end == utcDate(2026, 4, 12)) // the cycle before the anchor ends AT the anchor
  }

  /// One full cycle before the anchor: daysDiff −14 divides evenly (no extra −1 step),
  /// so the date is its own cycle start.
  @Test func periodStart_biweekly_exactlyOneCycleBeforeAnchor_isOwnCycleStart() {
    let anchor = utcDate(2026, 4, 12)
    let oneCycleBefore = utcDate(2026, 3, 29) // daysDiff = −14 → floorDiv = −1 exactly
    let result = PeriodCalculator.periodStart(
      containing: oneCycleBefore,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 3, 29)) // not Mar 15 — no double subtraction
  }

  /// For a fixed reference date, shifting the biweekly anchor by N < 14 days shifts the period
  /// start by N: editing a biweekly startDate re-slices its cycles (the Save-time re-anchor
  /// confirmation warns about this).
  @Test func periodStart_biweekly_anchorShift_shiftsCycleBoundariesBySameDelta() {
    let reference = utcDate(2026, 4, 20)
    let anchorA = utcDate(2026, 4, 1) // ref is 19 days out → cycle start anchor + 14
    let anchorB = utcDate(2026, 4, 4) // anchor moved +3 days
    let startA = PeriodCalculator.periodStart(
      containing: reference, period: .biweekly, weekStart: .sunday,
      biweeklyAnchor: anchorA, calendar: utcCalendar
    )
    let startB = PeriodCalculator.periodStart(
      containing: reference, period: .biweekly, weekStart: .sunday,
      biweeklyAnchor: anchorB, calendar: utcCalendar
    )
    #expect(startA == utcDate(2026, 4, 15))
    #expect(startB == utcDate(2026, 4, 18)) // phase moved with the anchor
    let deltaDays = utcCalendar.dateComponents([.day], from: startA, to: startB).day
    #expect(deltaDays == 3)
  }

  /// The re-anchor UX relies on biweekly being the ONLY period whose grid depends on the
  /// anchor; daily/weekly/monthly ignore `biweeklyAnchor`.
  @Test func periodStart_nonBiweekly_ignoresAnchorDelta() {
    let reference = utcDate(2026, 4, 20)
    let anchorA = utcDate(2026, 4, 1)
    let anchorB = utcDate(2026, 4, 4)
    for period in [RecurringBudgetPeriod.daily, .weekly, .monthly] {
      let startA = PeriodCalculator.periodStart(
        containing: reference, period: period, weekStart: .sunday,
        biweeklyAnchor: anchorA, calendar: utcCalendar
      )
      let startB = PeriodCalculator.periodStart(
        containing: reference, period: period, weekStart: .sunday,
        biweeklyAnchor: anchorB, calendar: utcCalendar
      )
      #expect(startA == startB, "period \(period) must ignore the biweekly anchor")
    }
  }

  /// Saturday week-start across a year boundary: Fri 2027-01-01 is in the week that began Sat 2026-12-26.
  @Test func periodStart_weekly_saturdayWeekStart_acrossYearBoundary() {
    let newYearsDay = utcDate(2027, 1, 1) // Friday
    let start = PeriodCalculator.periodStart(
      containing: newYearsDay,
      period: .weekly,
      weekStart: .saturday,
      biweeklyAnchor: newYearsDay,
      calendar: utcCalendar
    )
    #expect(start == utcDate(2026, 12, 26))
    let end = PeriodCalculator.periodEnd(
      containing: newYearsDay,
      period: .weekly,
      weekStart: .saturday,
      biweeklyAnchor: newYearsDay,
      calendar: utcCalendar
    )
    #expect(end == utcDate(2027, 1, 2))
  }

  // MARK: Monthly

  @Test func periodStart_monthly_returnsFirstOfMonth() {
    let mid = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodStart(
      containing: mid,
      period: .monthly,
      weekStart: .sunday,
      biweeklyAnchor: mid,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 1))
  }

  @Test func periodStart_monthly_onFirstDayReturnsSameDay() {
    let first = utcDate(2026, 4, 1)
    let result = PeriodCalculator.periodStart(
      containing: first,
      period: .monthly,
      weekStart: .sunday,
      biweeklyAnchor: first,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 1))
  }
}

// MARK: - PeriodCalculator.periodEnd

struct PeriodCalculatorPeriodEndTests {
  // MARK: All period types

  @Test func periodEnd_daily_isNextDay() {
    let date = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodEnd(
      containing: date,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: date,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 16))
  }

  @Test func periodEnd_weekly_sundayWeekStart_isNextSunday() {
    let wednesday = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodEnd(
      containing: wednesday,
      period: .weekly,
      weekStart: .sunday,
      biweeklyAnchor: wednesday,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 19))
  }

  @Test func periodEnd_biweekly_isFourteenDaysLater() {
    let anchor = utcDate(2026, 3, 29)
    let periodStartDate = utcDate(2026, 4, 12) // confirmed start of 2nd biweekly period
    let result = PeriodCalculator.periodEnd(
      containing: periodStartDate,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 26))
  }

  @Test func periodEnd_weekly_mondayWeekStart_isNextMonday() {
    let wednesday = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodEnd(
      containing: wednesday,
      period: .weekly,
      weekStart: .monday,
      biweeklyAnchor: wednesday,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 4, 20))
  }

  @Test func periodEnd_monthly_isFirstOfNextMonth() {
    let date = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodEnd(
      containing: date,
      period: .monthly,
      weekStart: .sunday,
      biweeklyAnchor: date,
      calendar: utcCalendar
    )
    #expect(result == utcDate(2026, 5, 1))
  }
}

// MARK: - PeriodCalculator.periodBoundaries

struct PeriodCalculatorBoundariesTests {
  /// Daily: 3-day gap returns 3 boundaries.
  @Test func periodBoundaries_daily_threeDayGap() {
    let result = PeriodCalculator.periodBoundaries(
      from: utcDate(2026, 4, 12),
      to: utcDate(2026, 4, 15),
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: utcDate(2026, 4, 12),
      calendar: utcCalendar
    )
    #expect(result == [utcDate(2026, 4, 12), utcDate(2026, 4, 13), utcDate(2026, 4, 14)])
  }

  /// Weekly (Sunday start): multi-week gap returns one boundary per week.
  @Test func periodBoundaries_weekly_threeWeeks() {
    let result = PeriodCalculator.periodBoundaries(
      from: utcDate(2026, 4, 5),
      to: utcDate(2026, 4, 20),
      period: .weekly,
      weekStart: .sunday,
      biweeklyAnchor: utcDate(2026, 4, 5),
      calendar: utcCalendar
    )
    #expect(result == [utcDate(2026, 4, 5), utcDate(2026, 4, 12), utcDate(2026, 4, 19)])
  }

  /// Empty result when start == end.
  @Test func periodBoundaries_emptyWhenStartEqualsEnd() {
    let date = utcDate(2026, 4, 12)
    let result = PeriodCalculator.periodBoundaries(
      from: date,
      to: date,
      period: .daily,
      weekStart: .sunday,
      biweeklyAnchor: date,
      calendar: utcCalendar
    )
    #expect(result.isEmpty)
  }

  /// Monthly: across a quarter boundary returns 3 boundaries.
  @Test func periodBoundaries_monthly_acrossQuarterBoundary() {
    let result = PeriodCalculator.periodBoundaries(
      from: utcDate(2026, 1, 1),
      to: utcDate(2026, 4, 1),
      period: .monthly,
      weekStart: .sunday,
      biweeklyAnchor: utcDate(2026, 1, 1),
      calendar: utcCalendar
    )
    #expect(result == [utcDate(2026, 1, 1), utcDate(2026, 2, 1), utcDate(2026, 3, 1)])
  }
}
