import Foundation
@testable import simple_recurring_budgets
import Testing

/// Covers the `app_opened` session gate (analytics-spec.md §9). The gate exists
/// so warm resumes from background re-fire `app_opened` (fixing the DAU/WAU/MAU
/// undercount) without double-counting rapid re-activations within one session.
@Suite("AppOpenTracker — app_opened session gate (§9)")
@MainActor
struct AppOpenTrackerTests {
  private let t0 = Date(timeIntervalSinceReferenceDate: 0)

  @Test("first foreground always fires")
  func firstForegroundFires() {
    let tracker = AppOpenTracker()
    #expect(tracker.registerForeground(now: t0) == true)
  }

  @Test("re-activation within the session gap does not re-fire")
  func withinSessionGapSuppressed() {
    let tracker = AppOpenTracker()
    #expect(tracker.registerForeground(now: t0) == true)
    // 29 minutes later — still the same session.
    #expect(tracker.registerForeground(now: t0.addingTimeInterval(29 * 60)) == false)
  }

  @Test("foreground at/after the session gap fires again")
  func afterSessionGapFires() {
    let tracker = AppOpenTracker()
    #expect(tracker.registerForeground(now: t0) == true)
    // Exactly the gap later counts as a new session.
    #expect(tracker.registerForeground(now: t0.addingTimeInterval(AppOpenTracker.sessionGap)) == true)
  }

  @Test("the window is measured from the last fire, not the last attempt")
  func gapMeasuredFromLastFire() {
    let tracker = AppOpenTracker()
    #expect(tracker.registerForeground(now: t0) == true)
    // A suppressed peek at +20m must NOT advance the window.
    #expect(tracker.registerForeground(now: t0.addingTimeInterval(20 * 60)) == false)
    // 45m after the original fire: still > gap from that fire, so it fires.
    #expect(tracker.registerForeground(now: t0.addingTimeInterval(45 * 60)) == true)
  }
}
