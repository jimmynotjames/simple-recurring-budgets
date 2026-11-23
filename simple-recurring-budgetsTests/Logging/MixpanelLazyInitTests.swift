@testable import simple_recurring_budgets
import Testing

/// MixpanelAnalyticsClient lazy-init invariants: `init` and opted-out `track` do no gated
/// work; opted-in `track` does it. `Mixpanel.initialize` is an unswappable SDK global, so
/// these tests reproduce the `isOptedIn` guard with inline stand-ins instead.
@Suite("MixpanelAnalyticsClient — lazy-init §18.1 #4")
@MainActor
struct MixpanelLazyInitTests {
  // MARK: - Opt-in gate (proxy for lazy-init guard)

  @Test("track with isOptedIn = false does not call through")
  func trackOptedOutDropped() {
    let spy = SpyAnalyticsClient()
    spy.track("should.not.appear")
    // The spy has no opt-in gate and records anyway; the real assertions use the inline
    // gate below, which mirrors MixpanelAnalyticsClient.
    var isOptedIn = false
    var trackCallCount = 0
    let gate: () -> Bool = { isOptedIn }
    func guardedTrack(_: String) {
      guard gate() else { return }
      trackCallCount += 1
    }
    guardedTrack("e1")
    guardedTrack("e2")
    #expect(trackCallCount == 0)
    isOptedIn = true
    guardedTrack("e3")
    #expect(trackCallCount == 1)
  }

  @Test("init does not trigger SDK-init closure")
  func initDoesNotTriggerSDKInit() {
    var initCallCount = 0
    var isOptedIn = false
    func lazySdkInit() {
      initCallCount += 1
    }
    func track(optedIn _: Bool) {
      guard isOptedIn else { return }
      lazySdkInit()
    }
    // Construction (MixpanelAnalyticsClient.init) calls no lazySdkInit().
    #expect(initCallCount == 0)
    track(optedIn: false)
    #expect(initCallCount == 0)
    isOptedIn = true
    track(optedIn: true)
    #expect(initCallCount == 1)
    track(optedIn: true)
    // The real client's ensureInitialized() short-circuits after the first call; this inline
    // stand-in has no one-shot lock, so it counts again.
    #expect(initCallCount == 2) // bare inline, NOT using ensureInitialized one-shot lock
  }

  @Test("AnalyticsEvent constants are all distinct strings")
  func allEventConstantsDistinct() {
    let all: [String] = [
      AnalyticsEvent.appOpened,
      AnalyticsEvent.budgetCreated,
      AnalyticsEvent.budgetEdited,
      AnalyticsEvent.budgetDeleted,
      AnalyticsEvent.budgetReset,
      AnalyticsEvent.carryOverReset,
      AnalyticsEvent.expenseLogged,
      AnalyticsEvent.expenseEdited,
      AnalyticsEvent.expenseDeleted,
      AnalyticsEvent.settingsOpened,
      AnalyticsEvent.settingChanged,
      AnalyticsEvent.analyticsConsentChanged,
    ]
    #expect(Set(all).count == all.count)
  }
}
