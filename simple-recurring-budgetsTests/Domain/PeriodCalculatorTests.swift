import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - Shared test calendar (3.1)

/// Fixed-UTC Gregorian calendar for deterministic date arithmetic in all PeriodCalculator tests.
private let utcCalendar: Calendar = {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  return cal
}()

/// Convenience: build a `Date` at midnight UTC for the given year/month/day.
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
  // MARK: 3.2 — Daily

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

  // MARK: 3.3 — Weekly

  /// 2026-04-15 is a Wednesday; with Sunday week-start the period began on 2026-04-12 (Sunday).
  @Test func periodStart_weekly_sundayWeekStart_returnsCorrectSunday() {
    let wednesday = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodStart(
      containing: wednesday,
      period: .weekly,
      weekStart: .sunday,
      biweeklyAnchor: wednesday,
      calendar: utcCalendar
    )
    // 2026-04-12 is a Sunday (verified: Jan 1, 2026 = Thursday; Apr 12 = day 102; (4+101)%7=0 → Sunday)
    #expect(result == utcDate(2026, 4, 12))
  }

  /// 2026-04-15 is a Wednesday; with Monday week-start the period began on 2026-04-13 (Monday).
  @Test func periodStart_weekly_mondayWeekStart_returnsCorrectMonday() {
    let wednesday = utcDate(2026, 4, 15)
    let result = PeriodCalculator.periodStart(
      containing: wednesday,
      period: .weekly,
      weekStart: .monday,
      biweeklyAnchor: wednesday,
      calendar: utcCalendar
    )
    // 2026-04-13 is a Monday (day 103; (4+102)%7=1 → Monday)
    #expect(result == utcDate(2026, 4, 13))
  }

  /// When the date itself is the week-start day, periodStart should return the same date.
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

  // MARK: 3.4 — Biweekly

  /// Budget created Wednesday 2026-04-01; week start = Sunday.
  /// Most recent Sunday at or before 2026-04-01 is 2026-03-29.
  /// Date under test: 2026-04-17 (Friday, 19 days after anchor).
  /// periodsElapsed = 19 / 14 = 1 → period start = anchor + 14 = 2026-04-12.
  @Test func periodStart_biweekly_correctCycleAlignment() {
    // 2026-03-29: day 88 from Jan 1 (0-indexed); (4+88)%7 = 92%7 = 1 → Monday? Let me recount.
    // Jan(31)+Feb(28)+Mar(29-1=28) = 88 days from Jan 1 (0-indexed, Jan 1=0).
    // Actually: Jan 1=day0, Jan 31=day30, Feb 28=day58, Mar 29=day87.
    // weekday = (4+87)%7 = 91%7 = 0 → Sunday. ✓ 2026-03-29 is Sunday.
    let anchor = utcDate(2026, 3, 29) // Sunday (biweekly anchor, derived from createdAt)
    let testDate = utcDate(2026, 4, 17) // 19 days after anchor → period 1 (14..27 days from anchor)
    let result = PeriodCalculator.periodStart(
      containing: testDate,
      period: .biweekly,
      weekStart: .sunday,
      biweeklyAnchor: anchor,
      calendar: utcCalendar
    )
    // Expected: anchor + 14 days = 2026-04-12
    #expect(result == utcDate(2026, 4, 12))
  }

  /// Date within the first biweekly period (before 14 days from anchor) returns the anchor itself.
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

  /// Dates BEFORE the anchor exercise `floorDiv`'s negative branch: daysDiff = −7
  /// gives floorDiv(−7, 14) = −1 (truncating division would give 0), so the date
  /// lands in the cycle starting anchor − 14 — never in a phantom cycle at the
  /// anchor itself. Load-bearing for back-dated snapshots and the #240 guarantee
  /// that biweekly phase math stays anchored to the budget's own startDate.
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

  /// Exactly one full cycle before the anchor: daysDiff = −14 divides evenly
  /// (remainder 0, no extra −1 step), so the date IS its own cycle start.
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

  /// Re-anchor regression (biweekly start-date edit): for a FIXED reference date,
  /// shifting the biweekly anchor by N days (N < 14) shifts the computed period
  /// start by the same N days — i.e. editing a biweekly budget's startDate
  /// re-slices its cycles, exactly as the Save-time re-anchor confirmation warns.
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

  /// Invariant the re-anchor UX relies on: biweekly is the ONLY period whose grid
  /// depends on the anchor. For daily/weekly/monthly, shifting `biweeklyAnchor`
  /// leaves the computed period start unchanged (they ignore the anchor).
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

  /// Saturday week-start across a year boundary: Fri 2027-01-01 belongs to the
  /// week that began Sat 2026-12-26.
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

  // MARK: 3.5 — Monthly

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
  // MARK: 3.6 — All four period types

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
    // Period start = 2026-04-12 (Sunday) + 7 = 2026-04-19
    // 2026-04-19: day 108 from Jan 1; (4+108)%7=0 → Sunday ✓
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
    // Period start = 2026-04-13 (Monday) + 7 = 2026-04-20
    // 2026-04-20: (4+109)%7=1 → Monday ✓
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
  // MARK: 3.7

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
    // 2026-04-05 is a Sunday: day 95 (Jan 1=day1); (4+94)%7=98%7=0 → Sunday ✓
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
