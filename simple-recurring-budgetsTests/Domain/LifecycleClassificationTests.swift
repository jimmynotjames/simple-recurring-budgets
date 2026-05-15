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
    #expect(isActive(periodStart: d(2026, 4, 15), periodEnd: d(2026, 4, 16), lifecycleEvents: []))
  }

  @Test func pauseActionPeriod_isActive() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let events = [pause]
    // The period containing the pause is active
    #expect(isActive(periodStart: d(2026, 4, 15), periodEnd: d(2026, 4, 16), lifecycleEvents: events))
  }

  @Test func periodAfterPause_isPaused() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let events = [pause]
    // The period AFTER the pause-action period is paused
    #expect(!isActive(periodStart: d(2026, 4, 16), periodEnd: d(2026, 4, 17), lifecycleEvents: events))
  }

  @Test func resumeActionPeriod_isActive() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 20, hour: 10))
    let events = [pause, resume]
    // Resume-action period is active
    #expect(isActive(periodStart: d(2026, 4, 20), periodEnd: d(2026, 4, 21), lifecycleEvents: events))
  }

  @Test func periodBetweenPauseAndResume_isPaused() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 20, hour: 10))
    let events = [pause, resume]
    // Apr 17 is between pause (Apr 15) and resume (Apr 20) → paused
    #expect(!isActive(periodStart: d(2026, 4, 17), periodEnd: d(2026, 4, 18), lifecycleEvents: events))
  }

  @Test func periodAfterResume_isActive() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 20, hour: 10))
    let events = [pause, resume]
    #expect(isActive(periodStart: d(2026, 4, 21), periodEnd: d(2026, 4, 22), lifecycleEvents: events))
  }

  @Test func multiplePauseCycles_correctClassification() {
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5, hour: 10))
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10, hour: 10))
    let pause2 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15, hour: 10))
    let events = [pause1, resume1, pause2]

    // Apr 7 (between pause1 and resume1) → paused
    #expect(!isActive(periodStart: d(2026, 4, 7), periodEnd: d(2026, 4, 8), lifecycleEvents: events))
    // Apr 12 (after resume1, before pause2) → active
    #expect(isActive(periodStart: d(2026, 4, 12), periodEnd: d(2026, 4, 13), lifecycleEvents: events))
    // Apr 17 (after pause2) → paused
    #expect(!isActive(periodStart: d(2026, 4, 17), periodEnd: d(2026, 4, 18), lifecycleEvents: events))
  }
}
