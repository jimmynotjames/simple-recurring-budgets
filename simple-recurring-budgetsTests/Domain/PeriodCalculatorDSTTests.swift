import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - DST / non-UTC time zones (test-coverage-audit-2026-06-10 E1)

/// Production runs `PeriodCalculator` on `Calendar.autoupdatingCurrent`, so
/// period boundaries must hold on real time zones across daylight-saving
/// transitions — days that are 23 or 25 wall-clock hours long. 2026
/// transitions: US spring-forward 2026-03-08 / fall-back 2026-11-01; EU
/// spring-forward 2026-03-29 / fall-back 2026-10-25.
struct PeriodCalculatorDSTTests {
  /// One DST transition-day fixture: `hours` is the expected wall-clock length
  /// of that day. A struct rather than a tuple (SwiftLint large_tuple);
  /// `nonisolated`/`Sendable` because `@Test(arguments:)` evaluates outside the
  /// default MainActor isolation.
  nonisolated struct TransitionDay {
    let zone: String
    let year: Int
    let month: Int
    let day: Int
    let hours: Int
  }

  nonisolated static let transitionDays: [TransitionDay] = [
    TransitionDay(zone: "America/Los_Angeles", year: 2026, month: 3, day: 8, hours: 23),
    TransitionDay(zone: "America/Los_Angeles", year: 2026, month: 11, day: 1, hours: 25),
    TransitionDay(zone: "Europe/Berlin", year: 2026, month: 3, day: 29, hours: 23),
    TransitionDay(zone: "Europe/Berlin", year: 2026, month: 10, day: 25, hours: 25),
    TransitionDay(zone: "UTC", year: 2026, month: 3, day: 8, hours: 24), // control: no transition
  ]

  /// Daily periods pin to local midnight on both sides of a transition, and the
  /// transition day's period is exactly the shortened/lengthened wall-clock day.
  @Test(arguments: transitionDays)
  func daily_transitionDay_startsAndEndsAtLocalMidnight(_ tz: TransitionDay) {
    let cal = TestCalendars.gregorian(in: tz.zone)
    let noon = TestCalendars.date(tz.year, tz.month, tz.day, hour: 12, in: cal)

    let start = PeriodCalculator.periodStart(
      containing: noon, period: .daily, weekStart: .sunday, biweeklyAnchor: noon, calendar: cal
    )
    let end = PeriodCalculator.periodEnd(
      containing: noon, period: .daily, weekStart: .sunday, biweeklyAnchor: noon, calendar: cal
    )

    #expect(start == TestCalendars.date(tz.year, tz.month, tz.day, in: cal))
    #expect(cal.component(.hour, from: start) == 0)
    #expect(cal.component(.hour, from: end) == 0)
    #expect(
      end.timeIntervalSince(start) == Double(tz.hours) * 3600,
      "the transition day's period must span exactly \(tz.hours) wall-clock hours"
    )
  }

  /// A weekly period containing the LA spring-forward keeps its local-midnight
  /// Sunday boundaries; the week is 167 absolute hours, not 168.
  @Test func weekly_acrossSpringForward_keepsLocalMidnightBoundaries() {
    let cal = TestCalendars.gregorian(in: "America/Los_Angeles")
    // 2026-03-10 is the Tuesday after the 2026-03-08 (Sunday) transition.
    let tuesday = TestCalendars.date(2026, 3, 10, hour: 9, in: cal)

    let start = PeriodCalculator.periodStart(
      containing: tuesday, period: .weekly, weekStart: .sunday, biweeklyAnchor: tuesday, calendar: cal
    )
    let end = PeriodCalculator.periodEnd(
      containing: tuesday, period: .weekly, weekStart: .sunday, biweeklyAnchor: tuesday, calendar: cal
    )

    #expect(start == TestCalendars.date(2026, 3, 8, in: cal))
    #expect(end == TestCalendars.date(2026, 3, 15, in: cal))
    #expect(end.timeIntervalSince(start) == 167 * 3600)
  }

  /// Monthly periods containing a transition keep first-of-month local
  /// midnights: March 2026 in LA is 743 absolute hours, November is 721.
  @Test(arguments: [
    (month: 3, hours: 743), // 31 days − 1h spring-forward
    (month: 11, hours: 721), // 30 days + 1h fall-back
  ])
  func monthly_acrossTransition_keepsFirstOfMonthBoundaries(_ arg: (month: Int, hours: Int)) {
    let cal = TestCalendars.gregorian(in: "America/Los_Angeles")
    let midMonth = TestCalendars.date(2026, arg.month, 15, hour: 12, in: cal)

    let start = PeriodCalculator.periodStart(
      containing: midMonth, period: .monthly, weekStart: .sunday, biweeklyAnchor: midMonth, calendar: cal
    )
    let end = PeriodCalculator.periodEnd(
      containing: midMonth, period: .monthly, weekStart: .sunday, biweeklyAnchor: midMonth, calendar: cal
    )

    #expect(start == TestCalendars.date(2026, arg.month, 1, in: cal))
    #expect(cal.component(.day, from: end) == 1)
    #expect(end.timeIntervalSince(start) == Double(arg.hours) * 3600)
  }

  /// Boundary enumeration across the transition yields exactly the local
  /// midnights — no skipped, duplicated, or hour-shifted boundary.
  @Test func boundaries_dailyAcrossSpringForward_areConsecutiveLocalMidnights() {
    let cal = TestCalendars.gregorian(in: "America/Los_Angeles")
    let from = TestCalendars.date(2026, 3, 6, in: cal)
    let to = TestCalendars.date(2026, 3, 11, in: cal)

    let boundaries = PeriodCalculator.periodBoundaries(
      from: from, to: to, period: .daily, weekStart: .sunday, biweeklyAnchor: from, calendar: cal
    )

    let expected = [6, 7, 8, 9, 10].map { TestCalendars.date(2026, 3, $0, in: cal) }
    #expect(boundaries == expected)
    for boundary in boundaries {
      #expect(cal.component(.hour, from: boundary) == 0, "every boundary must be a local midnight")
    }
    // The 03-08 → 03-09 step is the 23-hour day.
    #expect(boundaries[3].timeIntervalSince(boundaries[2]) == 23 * 3600)
  }
}
