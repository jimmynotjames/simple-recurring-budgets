import Foundation
@testable import simple_recurring_budgets
import Testing

private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day
  comps.hour = hour; comps.minute = 0; comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

struct LifecycleClassificationTests {
  @Test func noEvents_isAlwaysActive() {
    #expect(isActive(periodStart: d(2026, 4, 15), periodEnd: d(2026, 4, 16), sortedLifecycleEvents: []))
  }

  @Test func pauseActionPeriod_isActive() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let events = [pause]
    #expect(isActive(periodStart: d(2026, 4, 15), periodEnd: d(2026, 4, 16), sortedLifecycleEvents: events))
  }

  @Test func periodAfterPause_isPaused() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let events = [pause]
    #expect(!isActive(periodStart: d(2026, 4, 16), periodEnd: d(2026, 4, 17), sortedLifecycleEvents: events))
  }

  @Test func resumeActionPeriod_isActive() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 20, hour: 10))
    let events = [pause, resume]
    #expect(isActive(periodStart: d(2026, 4, 20), periodEnd: d(2026, 4, 21), sortedLifecycleEvents: events))
  }

  @Test func periodBetweenPauseAndResume_isPaused() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 20, hour: 10))
    let events = [pause, resume]
    #expect(!isActive(periodStart: d(2026, 4, 17), periodEnd: d(2026, 4, 18), sortedLifecycleEvents: events))
  }

  @Test func periodAfterResume_isActive() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 20, hour: 10))
    let events = [pause, resume]
    #expect(isActive(periodStart: d(2026, 4, 21), periodEnd: d(2026, 4, 22), sortedLifecycleEvents: events))
  }

  @Test func multiplePauseCycles_correctClassification() {
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5, hour: 10))
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10, hour: 10))
    let pause2 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let events = [pause1, resume1, pause2]

    // Apr 7 (between pause1 and resume1) paused; Apr 12 (after resume1) active; Apr 17 (after pause2) paused.
    #expect(!isActive(periodStart: d(2026, 4, 7), periodEnd: d(2026, 4, 8), sortedLifecycleEvents: events))
    #expect(isActive(periodStart: d(2026, 4, 12), periodEnd: d(2026, 4, 13), sortedLifecycleEvents: events))
    #expect(!isActive(periodStart: d(2026, 4, 17), periodEnd: d(2026, 4, 18), sortedLifecycleEvents: events))
  }

  // MARK: - Boundary edge cases

  @Test func eventOnPeriodStart_makesPeriodActive() {
    // An event exactly at periodStart is inside [periodStart, periodEnd).
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15))
    #expect(isActive(periodStart: d(2026, 4, 15), periodEnd: d(2026, 4, 16), sortedLifecycleEvents: [pause]))
  }

  @Test func eventExactlyOnPeriodEnd_doesNotMakePeriodActive() {
    // periodEnd is exclusive: the Apr 16 pause belongs to the next period, so Apr 15 falls
    // back to the prior state (the Apr 1 resume).
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 1))
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 16))
    #expect(isActive(periodStart: d(2026, 4, 15), periodEnd: d(2026, 4, 16), sortedLifecycleEvents: [resume, pause]))
  }

  @Test func sameDayPauseThenResume_inSamePeriod_periodIsActive() {
    // Pause then resume within one period (e.g. misclick): that period is active, and later
    // periods follow the resume.
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 9))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 15, hour: 14))
    let events = [pause, resume]
    #expect(isActive(periodStart: d(2026, 4, 15), periodEnd: d(2026, 4, 16), sortedLifecycleEvents: events))
    #expect(isActive(periodStart: d(2026, 4, 16), periodEnd: d(2026, 4, 17), sortedLifecycleEvents: events))
  }

  @Test func longPause_acrossManyPeriods_allInternalPeriodsArePaused() {
    // Exercises the early-termination + reverse-iteration logic over a deep history.
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 1, 1))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 12, 1))
    let events = [pause, resume]
    for month in 2 ... 11 {
      #expect(!isActive(
        periodStart: d(2026, month, 15),
        periodEnd: d(2026, month, 16),
        sortedLifecycleEvents: events
      ), "Month \(month) should be paused")
    }
  }
}
