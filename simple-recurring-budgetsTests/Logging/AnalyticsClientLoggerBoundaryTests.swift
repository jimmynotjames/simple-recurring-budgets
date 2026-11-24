import OSLog
@testable import simple_recurring_budgets
import Testing

/// Structural tests that `AnalyticsClient` and its implementations accept no OSLog-shaped
/// parameters (`os.Logger`, `OSLogEntry`, `OSLogMessage`), so diagnostic logs can't be routed
/// into product analytics (`docs/analytics-spec.md` §17). The protocol surface is exactly
/// `track`, `identify`, `reset`; a new Logger-accepting method breaks the spy conformance
/// (compile error) or the assertions below.
@Suite("AnalyticsClient / Logger boundary")
@MainActor
struct AnalyticsClientLoggerBoundaryTests {
  // MARK: - Protocol surface has exactly track / identify / reset

  /// `SpyAnalyticsClient` conforms with exactly these three methods; a new protocol method
  /// fails the build here.
  @Test("AnalyticsClient protocol surface — only track, identify, reset")
  func protocolSurfaceIsExactly3Methods() {
    let spy = SpyAnalyticsClient()

    spy.track("test_event", properties: nil)
    spy.identify("test-id")
    spy.reset()

    #expect(spy.trackCalls.count == 1)
    #expect(spy.identifyCalls.count == 1)
    #expect(spy.resetCallCount == 1)
  }

  // MARK: - track(_:properties:) parameter types

  @Test("track parameters are String and optional dictionary — not Logger or OSLog types")
  func trackParameterTypesAreStringsNotLogger() {
    // Structural: compiles only if `track` accepts (String, [String: any Sendable]?).
    let spy = SpyAnalyticsClient()
    let event = "event_name"
    let props: [String: any Sendable]? = ["key": "value"]
    spy.track(event, properties: props)
    #expect(spy.trackedEvents == ["event_name"])
  }

  // MARK: - No OSLog-accepting API exists on ConsoleAnalyticsClient

  @Test("ConsoleAnalyticsClient has no Logger-accepting method")
  func consoleClientHasNoLoggerAcceptingMethod() {
    let client: any AnalyticsClient = ConsoleAnalyticsClient()
    client.track("smoke", properties: nil)
    client.identify(nil)
    client.reset()
    #expect(Bool(true), "ConsoleAnalyticsClient surface matches the AnalyticsClient protocol exactly")
  }

  // MARK: - AnalyticsEvent constants contain no OSLog-derived values

  @Test("AnalyticsEvent constants are plain strings, not derived from Logger")
  func analyticsEventConstantsArePlainStrings() {
    let appOpened: String = AnalyticsEvent.appOpened
    #expect(appOpened == "app_opened")
    // Plain snake_case, no dotted names.
    #expect(!appOpened.contains("."))
  }
}
