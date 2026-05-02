@testable import simple_recurring_budgets
import Testing

// MARK: - Protocol default overload

@Suite("AnalyticsClient — convenience overload")
@MainActor
struct AnalyticsClientOverloadTests {
  @Test("track(_:) forwards nil properties")
  func noArgConvenienceForwardsNilProperties() {
    let spy = SpyAnalyticsClient()
    spy.track("some.event")

    #expect(spy.trackCalls.count == 1)
    #expect(spy.trackCalls[0].event == "some.event")
    #expect(spy.trackCalls[0].properties == nil)
  }
}

// MARK: - SpyAnalyticsClient recording

@Suite("SpyAnalyticsClient — call recording")
@MainActor
struct SpyAnalyticsClientTests {
  @Test("records track calls in order with all metadata")
  func recordsTrackCallsInOrder() {
    let spy = SpyAnalyticsClient()
    spy.track("event.a", properties: nil)
    spy.track("event.b", properties: ["key": "value"])

    #expect(spy.trackedEvents == ["event.a", "event.b"])
    #expect(spy.trackCalls[1].properties == ["key": "value"])
  }

  @Test("records identify calls")
  func recordsIdentifyCalls() {
    let spy = SpyAnalyticsClient()
    spy.identify("user-123")
    spy.identify(nil)

    #expect(spy.identifyCalls.count == 2)
    #expect(spy.identifyCalls[0] == "user-123")
    #expect(spy.identifyCalls[1] == nil)
  }

  @Test("counts reset calls")
  func countsResetCalls() {
    let spy = SpyAnalyticsClient()
    spy.reset()
    spy.reset()

    #expect(spy.resetCallCount == 2)
  }
}

// MARK: - ConsoleAnalyticsClient crash safety

@Suite("ConsoleAnalyticsClient — crash safety")
@MainActor
struct ConsoleAnalyticsClientTests {
  @Test("nil properties does not crash")
  func nilPropertiesNoCrash() {
    let client = ConsoleAnalyticsClient()
    client.track("event.nil", properties: nil)
  }

  @Test("empty properties does not crash")
  func emptyPropertiesNoCrash() {
    let client = ConsoleAnalyticsClient()
    client.track("event.empty", properties: [:])
  }

  @Test("mixed value types does not crash")
  func mixedPropertiesNoCrash() {
    let client = ConsoleAnalyticsClient()
    client.track("event.mixed", properties: [
      "string": "hello",
      "int": 42,
      "bool": true,
    ])
  }

  @Test("identify does not crash")
  func identifyNoCrash() {
    let client = ConsoleAnalyticsClient()
    client.identify(nil)
    client.identify("user-abc")
  }

  @Test("reset does not crash")
  func resetNoCrash() {
    let client = ConsoleAnalyticsClient()
    client.reset()
  }
}

// MARK: - AnalyticsEvent constants

@Suite("AnalyticsEvent — constant values")
@MainActor
struct AnalyticsEventTests {
  @Test("appOpened has expected string value")
  func appOpenedConstant() {
    #expect(AnalyticsEvent.appOpened == "app_opened")
  }
}
