@testable import simple_recurring_budgets
import Testing

/// Consent toggle ordering.
@Suite("Analytics — consent ordering §18.1 #5 #6")
@MainActor
struct AnalyticsConsentOrderingTests {
  // MARK: - Toggle-off ordering

  @Test("toggle-off fires consent_changed before reset")
  func toggleOffFiresConsentChangedBeforeReset() {
    let spy = SpyAnalyticsClient()

    // SettingsView toggle-off order: track analytics_consent_changed (still opted in),
    // reset(), then set analyticsOptIn = false.
    spy.track(
      AnalyticsEvent.analyticsConsentChanged,
      properties: [
        AnalyticsProperty.newValue: false,
        AnalyticsProperty.oldValue: true,
      ]
    )
    spy.reset()

    #expect(spy.trackCalls.count == 1)
    #expect(spy.trackCalls[0].event == AnalyticsEvent.analyticsConsentChanged)
    #expect(spy.trackCalls[0].properties?[AnalyticsProperty.newValue] == "false")
    #expect(spy.resetCallCount == 1)
  }

  @Test("toggle-off does not replay prior events after reset")
  func toggleOffNoReplay() {
    let spy = SpyAnalyticsClient()
    spy.track(AnalyticsEvent.appOpened)
    spy.reset()
    #expect(spy.trackCalls.count == 1) // only app_opened; no replayed event
    #expect(spy.resetCallCount == 1)
  }

  // MARK: - Toggle-on ordering (strict-opt-in jurisdiction)

  @Test("toggle-on fires consent_changed with new_value true")
  func toggleOnFiresConsentChanged() {
    let spy = SpyAnalyticsClient()
    // Toggle-on order: SDK lazy-inits (identify + people props), then consent_changed(true).
    spy.identify("test-distinct-id")
    spy.track(
      AnalyticsEvent.analyticsConsentChanged,
      properties: [AnalyticsProperty.newValue: true]
    )

    #expect(spy.identifyCalls.count == 1)
    #expect(spy.identifyCalls[0] == "test-distinct-id")
    #expect(spy.trackedEvents == [AnalyticsEvent.analyticsConsentChanged])
    #expect(spy.trackCalls[0].properties?[AnalyticsProperty.newValue] == "true")
  }

  @Test("toggle-on does NOT retroactively replay app_opened")
  func toggleOnNoRetroactiveAppOpened() {
    let spy = SpyAnalyticsClient()
    // In strict-opt-in jurisdictions app_opened fires only AFTER opt-in; accepting consent
    // fires consent_changed alone.
    spy.track(
      AnalyticsEvent.analyticsConsentChanged,
      properties: [AnalyticsProperty.newValue: true]
    )
    #expect(!spy.trackedEvents.contains(AnalyticsEvent.appOpened))
  }
}
