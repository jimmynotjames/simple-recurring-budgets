//
//  AnalyticsClientTests.swift
//  simple-recurring-budgetsTests
//

import Testing
@testable import simple_recurring_budgets

// MARK: - Protocol default overloads

@Suite("AnalyticsClient — convenience overloads")
@MainActor
struct AnalyticsClientOverloadTests {

    @Test("track(_:properties:) defaults to .product channel at .info level")
    func productOverloadDefaults() {
        let spy = SpyAnalyticsClient()
        spy.track("some.event", properties: nil)

        #expect(spy.trackCalls.count == 1)
        #expect(spy.trackCalls[0].event == "some.event")
        #expect(spy.trackCalls[0].channel == .product)
        #expect(spy.trackCalls[0].level == .info)
        #expect(spy.trackCalls[0].properties == nil)
    }

    @Test("track(_:) no-arg convenience forwards nil properties")
    func noArgConvenienceForwardsNilProperties() {
        let spy = SpyAnalyticsClient()
        spy.track("some.event")

        #expect(spy.trackCalls[0].properties == nil)
        #expect(spy.trackCalls[0].channel == .product)
    }

    @Test("track(_:channel:level:) diagnostic convenience forwards nil properties")
    func diagnosticConvenienceForwardsNilProperties() {
        let spy = SpyAnalyticsClient()
        spy.track("cloudkit.event", channel: .cloudKit, level: .notice)

        #expect(spy.trackCalls.count == 1)
        #expect(spy.trackCalls[0].channel == .cloudKit)
        #expect(spy.trackCalls[0].level == .notice)
        #expect(spy.trackCalls[0].properties == nil)
    }

    @Test("track(_:channel:level:) defaults level to .info")
    func diagnosticConvenienceDefaultsLevelToInfo() {
        let spy = SpyAnalyticsClient()
        spy.track("bootstrap.event", channel: .bootstrap)

        #expect(spy.trackCalls[0].level == .info)
    }
}

// MARK: - SpyAnalyticsClient recording

@Suite("SpyAnalyticsClient — call recording")
@MainActor
struct SpyAnalyticsClientTests {

    @Test("records track calls in order with all metadata")
    func recordsTrackCallsInOrder() {
        let spy = SpyAnalyticsClient()
        spy.track("event.a", channel: .product, level: .info, properties: nil)
        spy.track("event.b", channel: .cloudKit, level: .error, properties: ["key": "value"])

        #expect(spy.trackedEvents == ["event.a", "event.b"])
        #expect(spy.trackCalls[1].channel == .cloudKit)
        #expect(spy.trackCalls[1].level == .error)
        #expect(spy.trackCalls[1].properties == ["key": "value"])
    }

    @Test("productEvents filters to .product channel only")
    func productEventsFilter() {
        let spy = SpyAnalyticsClient()
        spy.track("product.event", channel: .product, level: .info, properties: nil)
        spy.track("cloudkit.event", channel: .cloudKit, level: .info, properties: nil)

        #expect(spy.productEvents.count == 1)
        #expect(spy.productEvents[0].event == "product.event")
    }

    @Test("diagnosticEvents excludes .product channel")
    func diagnosticEventsFilter() {
        let spy = SpyAnalyticsClient()
        spy.track("product.event", channel: .product, level: .info, properties: nil)
        spy.track("bootstrap.event", channel: .bootstrap, level: .info, properties: nil)
        spy.track("cloudkit.event", channel: .cloudKit, level: .notice, properties: nil)

        #expect(spy.diagnosticEvents.count == 2)
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

    @Test("product channel with nil properties does not crash")
    func productNilPropertiesNoCrash() {
        let client = ConsoleAnalyticsClient()
        client.track("event.nil", channel: .product, level: .info, properties: nil)
    }

    @Test("product channel with empty properties does not crash")
    func productEmptyPropertiesNoCrash() {
        let client = ConsoleAnalyticsClient()
        client.track("event.empty", channel: .product, level: .info, properties: [:])
    }

    @Test("product channel with mixed value types does not crash")
    func productMixedPropertiesNoCrash() {
        let client = ConsoleAnalyticsClient()
        client.track("event.mixed", channel: .product, level: .info, properties: [
            "string": "hello",
            "int": 42,
            "bool": true
        ])
    }

    @Test("bootstrap diagnostic channel does not crash")
    func bootstrapChannelNoCrash() {
        let client = ConsoleAnalyticsClient()
        client.track("bootstrap.event", channel: .bootstrap, level: .info, properties: nil)
    }

    @Test("cloudKit diagnostic channel at notice level does not crash")
    func cloudKitNoticeNoCrash() {
        let client = ConsoleAnalyticsClient()
        client.track("cloudkit.fallback", channel: .cloudKit, level: .notice, properties: nil)
    }

    @Test("cloudKit diagnostic channel at error level with properties does not crash")
    func cloudKitErrorWithPropertiesNoCrash() {
        let client = ConsoleAnalyticsClient()
        client.track("cloudkit.failed", channel: .cloudKit, level: .error, properties: [
            "error": "Something went wrong"
        ])
    }

    @Test("ui diagnostic channel does not crash")
    func uiChannelNoCrash() {
        let client = ConsoleAnalyticsClient()
        client.track("ui.event", channel: .ui, level: .info, properties: nil)
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

    @Test("product event name constants have expected string values")
    func productEventConstants() {
        #expect(AnalyticsEvent.appLaunched == "app.launched")
    }

    @Test("cloudKit diagnostic event name constants have expected string values")
    func cloudKitEventConstants() {
        #expect(AnalyticsEvent.cloudKitContainerBacked        == "cloudkit.container.backed")
        #expect(AnalyticsEvent.cloudKitContainerLocalFallback == "cloudkit.container.localFallback")
        #expect(AnalyticsEvent.cloudKitContainerLocalSuccess  == "cloudkit.container.localSuccess")
        #expect(AnalyticsEvent.cloudKitContainerFailed        == "cloudkit.container.failed")
    }
}
