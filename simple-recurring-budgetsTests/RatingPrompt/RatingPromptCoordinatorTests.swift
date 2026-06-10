import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("Rating prompt — eligibility & request (F-6.03)")
@MainActor
struct RatingPromptCoordinatorTests {
  // A fixed install date and a deterministic UTC calendar so day math is stable.
  static let installDate = Date(timeIntervalSinceReferenceDate: 600_000_000)
  static var utcCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }

  /// Bundles the coordinator under test with its state and spy for assertions.
  private struct Harness {
    let coordinator: RatingPromptCoordinator
    let state: RatingPromptState
    let spy: SpyAnalyticsClient
  }

  /// Builds a coordinator over a fresh in-memory store seeded with `installDate`,
  /// plus the spy analytics client for assertions.
  private func makeHarness() -> Harness {
    let store = MockKeyValueStore()
    store.seedExternal(
      string: Self.installDate.timeIntervalSinceReferenceDate.description,
      forKey: RatingPromptState.installedAtKey
    )
    let state = RatingPromptState(store: store)
    let spy = SpyAnalyticsClient()
    let coordinator = RatingPromptCoordinator(
      state: state, analytics: spy, calendar: Self.utcCalendar
    )
    return Harness(coordinator: coordinator, state: state, spy: spy)
  }

  private func day(_ offset: Int) -> Date {
    Self.installDate.addingTimeInterval(Double(offset) * 86400)
  }

  /// Drives the coordinator to the eligibility threshold: 10 logs across 3 distinct
  /// days, all on an active, non-deficit budget. The final log is on day 12.
  @discardableResult
  private func driveToEligible(
    _ coordinator: RatingPromptCoordinator,
    appVersion: String = "1.0"
  ) -> Date {
    for _ in 0 ..< 8 {
      coordinator.recordExpenseLogged(
        isActiveBudget: true, remainingIsNonNegative: true, now: day(10), appVersion: appVersion
      )
    }
    coordinator.recordExpenseLogged(
      isActiveBudget: true, remainingIsNonNegative: true, now: day(11), appVersion: appVersion
    )
    coordinator.recordExpenseLogged(
      isActiveBudget: true, remainingIsNonNegative: true, now: day(12), appVersion: appVersion
    )
    return day(12)
  }

  // MARK: - Tracking

  @Test("install date is stamped once and not overwritten")
  func installDateStableAcrossInits() {
    let store = MockKeyValueStore()
    let first = RatingPromptState(store: store)
    let stamped = first.installedAt
    let second = RatingPromptState(store: store)
    #expect(second.installedAt == stamped)
  }

  @Test("a successful log advances lifetime and distinct-day counters")
  func countersAdvance() {
    let harness = makeHarness()
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(1))
    #expect(harness.state.loggedExpenseCount == 1)
    #expect(harness.state.distinctLogDayCount == 1)
  }

  @Test("distinct-day count increments only on a new calendar day")
  func distinctDayOnlyOnNewDay() {
    let harness = makeHarness()
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(1))
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(1))
    #expect(harness.state.distinctLogDayCount == 1)
    #expect(harness.state.loggedExpenseCount == 2)
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(2))
    #expect(harness.state.distinctLogDayCount == 2)
  }

  // MARK: - Eligibility

  @Test("all thresholds met on a non-deficit active log → pending + eligible event once")
  func eligibleWhenAllThresholdsMet() {
    let harness = makeHarness()
    driveToEligible(harness.coordinator)
    #expect(harness.coordinator.isRequestPending)
    #expect(harness.state.firstEligibleAt != nil)
    #expect(harness.spy.trackedEvents.count(where: { $0 == AnalyticsEvent.ratingPromptEligible }) == 1)
  }

  @Test("rating-prompt people properties fire through the AnalyticsClient protocol")
  func peoplePropertiesObservableThroughProtocol() {
    // Pre-protocol-widening these went through an `as? MixpanelAnalyticsClient`
    // downcast and were unobservable under the spy (audit 2026-06-10 §4.3).
    let harness = makeHarness()
    let eligibleAt = driveToEligible(harness.coordinator)
    #expect(harness.spy.ratingPromptFirstEligibleDates == [eligibleAt])
    harness.coordinator.consumePendingRequest(now: day(13), appVersion: "1.0")
    #expect(harness.spy.ratingPromptLastRequestedDates == [day(13)])
  }

  @Test("a deficit-producing log is never eligible")
  func deficitLogNotEligible() {
    let harness = makeHarness()
    // 9 qualifying logs to clear count/day thresholds, then a deficit log.
    for _ in 0 ..< 8 {
      harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(10))
    }
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(11))
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: false, now: day(12))
    #expect(!harness.coordinator.isRequestPending)
    #expect(!harness.spy.trackedEvents.contains(AnalyticsEvent.ratingPromptEligible))
  }

  @Test("a log on a non-active budget is never eligible")
  func nonActiveLogNotEligible() {
    let harness = makeHarness()
    for _ in 0 ..< 8 {
      harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(10))
    }
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(11))
    harness.coordinator.recordExpenseLogged(isActiveBudget: false, remainingIsNonNegative: true, now: day(12))
    #expect(!harness.coordinator.isRequestPending)
  }

  @Test("below the lifetime-count threshold is not eligible")
  func belowCountThresholdNotEligible() {
    let harness = makeHarness()
    // 3 distinct days, install age fine, but only 3 logs (< 10).
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(10))
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(11))
    harness.coordinator.recordExpenseLogged(isActiveBudget: true, remainingIsNonNegative: true, now: day(12))
    #expect(!harness.coordinator.isRequestPending)
  }

  @Test("install age below 7 days is not eligible")
  func belowInstallAgeNotEligible() {
    let harness = makeHarness()
    // 10 logs but all within the first few days post-install.
    for i in 0 ..< 10 {
      harness.coordinator.recordExpenseLogged(
        isActiveBudget: true, remainingIsNonNegative: true, now: day(i % 3)
      )
    }
    #expect(!harness.coordinator.isRequestPending)
  }

  // MARK: - Request + once-per-version guard

  @Test("consume fires rating_prompt_requested, records the version, clears pending")
  func consumeRecordsVersion() {
    let harness = makeHarness()
    let last = driveToEligible(harness.coordinator, appVersion: "1.0")
    harness.coordinator.consumePendingRequest(now: last, appVersion: "1.0")
    #expect(!harness.coordinator.isRequestPending)
    #expect(harness.state.lastRequestedVersion == "1.0")
    #expect(harness.spy.trackedEvents.contains(AnalyticsEvent.ratingPromptRequested))
    let requested = harness.spy.trackCalls.first { $0.event == AnalyticsEvent.ratingPromptRequested }
    #expect(requested?.properties?[AnalyticsProperty.timeSinceFirstEligibleBucket] != nil)
  }

  @Test("already asked this version → no new request; a new version re-asks")
  func oncePerVersionGuard() {
    let harness = makeHarness()
    driveToEligible(harness.coordinator, appVersion: "1.0")
    harness.coordinator.consumePendingRequest(now: day(12), appVersion: "1.0")

    // Same version, another eligible log: not pending again.
    harness.coordinator.recordExpenseLogged(
      isActiveBudget: true, remainingIsNonNegative: true, now: day(13), appVersion: "1.0"
    )
    #expect(!harness.coordinator.isRequestPending)

    // New version: eligible again.
    harness.coordinator.recordExpenseLogged(
      isActiveBudget: true, remainingIsNonNegative: true, now: day(14), appVersion: "1.1"
    )
    #expect(harness.coordinator.isRequestPending)
  }

  @Test("eligible event fires at most once across multiple eligible logs")
  func eligibleEventFiresOnce() {
    let harness = makeHarness()
    driveToEligible(harness.coordinator)
    harness.coordinator.recordExpenseLogged(
      isActiveBudget: true, remainingIsNonNegative: true, now: day(13)
    )
    #expect(harness.spy.trackedEvents.count(where: { $0 == AnalyticsEvent.ratingPromptEligible }) == 1)
  }

  @Test("no shown/resolved events are ever emitted")
  func noOutcomeEvents() {
    let harness = makeHarness()
    driveToEligible(harness.coordinator)
    harness.coordinator.consumePendingRequest(now: day(12))
    #expect(!harness.spy.trackedEvents.contains("rating_prompt_shown"))
    #expect(!harness.spy.trackedEvents.contains("rating_prompt_resolved"))
  }

  // MARK: - Presenter gate (W1)

  @Test("presenter requests only when pending AND no sheet AND scene active")
  func presenterGate() {
    // The one true case.
    #expect(RatingPromptCoordinator.shouldRequestReview(
      isRequestPending: true, sheetIsPresented: false, sceneIsActive: true
    ))
    // A sheet is still up (the Add Expense sheet hasn't dismissed) → wait.
    #expect(!RatingPromptCoordinator.shouldRequestReview(
      isRequestPending: true, sheetIsPresented: true, sceneIsActive: true
    ))
    // Scene not active (backgrounded) → wait.
    #expect(!RatingPromptCoordinator.shouldRequestReview(
      isRequestPending: true, sheetIsPresented: false, sceneIsActive: false
    ))
    // No pending request → inert.
    #expect(!RatingPromptCoordinator.shouldRequestReview(
      isRequestPending: false, sheetIsPresented: false, sceneIsActive: true
    ))
  }

  // MARK: - Consent independence (S1, S2)

  /// Coordinator wired to an opted-out analytics client (drops every event),
  /// mirroring `MixpanelAnalyticsClient`'s `guard isOptedIn()`.
  private struct OptedOutHarness {
    let coordinator: RatingPromptCoordinator
    let state: RatingPromptState
    let spy: ConsentGatedSpy
  }

  private func makeOptedOut() -> OptedOutHarness {
    let store = MockKeyValueStore()
    store.seedExternal(
      string: Self.installDate.timeIntervalSinceReferenceDate.description,
      forKey: RatingPromptState.installedAtKey
    )
    let state = RatingPromptState(store: store)
    let spy = ConsentGatedSpy(optedIn: false)
    let coordinator = RatingPromptCoordinator(
      state: state, analytics: spy, calendar: Self.utcCalendar
    )
    return OptedOutHarness(coordinator: coordinator, state: state, spy: spy)
  }

  @Test("counters and eligibility advance even when analytics is opted out (S1)")
  func countersIndependentOfConsent() {
    let harness = makeOptedOut()
    driveToEligible(harness.coordinator)
    #expect(harness.state.loggedExpenseCount == 10)
    #expect(harness.state.distinctLogDayCount == 3)
    #expect(harness.coordinator.isRequestPending)
  }

  @Test("no rating events are transmitted when opted out (S2)")
  func noEventsWhenOptedOut() {
    let harness = makeOptedOut()
    driveToEligible(harness.coordinator)
    harness.coordinator.consumePendingRequest(now: day(12))
    #expect(harness.spy.tracked.isEmpty)
  }
}

/// Test double that mirrors `MixpanelAnalyticsClient`'s consent gate: events are
/// recorded only when opted in, dropped otherwise. Used for the S1/S2 contracts.
/// `@MainActor` so the mutable buffer is actor-protected (satisfies `Sendable`),
/// matching `SpyAnalyticsClient`.
@MainActor
private final class ConsentGatedSpy: AnalyticsClient {
  let optedIn: Bool
  private(set) var tracked: [String] = []

  init(optedIn: Bool) {
    self.optedIn = optedIn
  }

  nonisolated func track(_ event: String, properties _: [String: any Sendable]?) {
    MainActor.assumeIsolated {
      if optedIn { tracked.append(event) }
    }
  }

  nonisolated func identify(_: String?) {}
  nonisolated func reset() {}
}
