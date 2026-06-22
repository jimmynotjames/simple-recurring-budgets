@testable import simple_recurring_budgets
import SwiftUI
import Testing

/// Covers when `app_opened` fires (analytics-spec.md §9): on cold launch and on
/// a real return from background, but not on transient `.inactive` interruptions
/// (notification shade, Face ID, app switcher) and not on non-active phases.
@Suite("AppOpenTracker — app_opened on foreground (§9)")
@MainActor
struct AppOpenTrackerTests {
  @Test("cold launch (first .active) fires")
  func coldLaunchFires() {
    let tracker = AppOpenTracker()
    #expect(tracker.shouldFire(for: .active) == true)
  }

  @Test("return from background to active fires")
  func backgroundToActiveFires() {
    let tracker = AppOpenTracker()
    _ = tracker.shouldFire(for: .active) // cold launch
    #expect(tracker.shouldFire(for: .background) == false)
    #expect(tracker.shouldFire(for: .active) == true)
  }

  @Test("inactive flicker (active → inactive → active) does not fire")
  func inactiveFlickerSuppressed() {
    let tracker = AppOpenTracker()
    _ = tracker.shouldFire(for: .active) // cold launch
    #expect(tracker.shouldFire(for: .inactive) == false)
    // Returned from .inactive (not background) — a flicker, not a real open.
    #expect(tracker.shouldFire(for: .active) == false)
  }

  @Test("non-active phases never fire")
  func nonActiveNeverFires() {
    let tracker = AppOpenTracker()
    #expect(tracker.shouldFire(for: .background) == false)
    #expect(tracker.shouldFire(for: .inactive) == false)
  }
}
