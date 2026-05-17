import Foundation
@testable import simple_recurring_budgets
import Testing

private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day
  comps.hour = hour; comps.minute = minute; comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

// MARK: - isPausedAtMoment contract (F-7.06 moment-granular UI classifier)

struct IsPausedAtMomentTests {
  @Test func emptyHistory_returnsFalse() {
    #expect(!isPausedAtMoment(now: d(2026, 4, 15), sortedLifecycleEvents: []))
  }

  @Test func singlePauseBeforeNow_returnsTrue() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 14))
    #expect(isPausedAtMoment(now: d(2026, 4, 10, hour: 14, minute: 1), sortedLifecycleEvents: [pause]))
  }

  @Test func singlePauseAfterNow_returnsFalse() {
    // Pause is scheduled later than `now` (defensive — shouldn't happen via UI but possible via direct write).
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 14))
    #expect(!isPausedAtMoment(now: d(2026, 4, 10, hour: 13), sortedLifecycleEvents: [pause]))
  }

  @Test func pauseExactlyAtNow_returnsFalse() {
    // Boundary: effectiveDate == now → strict less-than → still active at the exact
    // pause moment. The transition happens at the next instant, which matches the
    // math classifier (pause-action period is itself active).
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 14))
    #expect(!isPausedAtMoment(now: d(2026, 4, 10, hour: 14), sortedLifecycleEvents: [pause]))
  }

  @Test func pauseThenResume_returnsFalse() {
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 15))
    #expect(!isPausedAtMoment(now: d(2026, 4, 20), sortedLifecycleEvents: [pause, resume]))
  }

  @Test func pauseResumePause_returnsTrue() {
    let pause1 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 5))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10))
    let pause2 = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 15))
    #expect(isPausedAtMoment(now: d(2026, 4, 20), sortedLifecycleEvents: [pause1, resume, pause2]))
  }

  @Test func allResumes_returnsFalse() {
    // Defensive — a budget with only `.resume` events (e.g., via direct write) should not be paused.
    let resume1 = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 5))
    let resume2 = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10))
    #expect(!isPausedAtMoment(now: d(2026, 4, 20), sortedLifecycleEvents: [resume1, resume2]))
  }

  @Test func samePeriodPauseThenResume_returnsFalse() {
    // Same-period pause/resume should net to active (latest event wins).
    let pause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 4, 10, hour: 9))
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10, hour: 11))
    #expect(!isPausedAtMoment(now: d(2026, 4, 10, hour: 12), sortedLifecycleEvents: [pause, resume]))
  }

  @Test func futurePauseIsIgnored_currentStateFromPriorEvents() {
    // A future-scheduled pause does not affect "now"; the most recent event ≤ now is the resume.
    let resume = LifecycleEvent(kind: .resume, effectiveDate: d(2026, 4, 10))
    let futurePause = LifecycleEvent(kind: .pause, effectiveDate: d(2026, 5, 1))
    #expect(!isPausedAtMoment(now: d(2026, 4, 20), sortedLifecycleEvents: [resume, futurePause]))
  }
}
