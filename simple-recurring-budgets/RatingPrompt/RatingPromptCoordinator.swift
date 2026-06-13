import Foundation
import Observation

/// Decision core for the automatic App Store review prompt (F-6.03).
///
/// On each successful Add-mode expense log the view calls `recordExpenseLogged`,
/// which advances the persisted eligibility counters and — when the balanced-profile
/// thresholds are met at a positive moment and we have not already asked for the
/// current app version — sets `isRequestPending`. The root presenter
/// (`ratingPromptPresenter()`) observes that flag and invokes Apple's native
/// `requestReview` once the Add Expense sheet has dismissed and the scene is active,
/// then calls `consumePendingRequest`.
///
/// No custom rating dialog is ever shown. Re-prompt prevention relies on Apple's
/// automatic throttling plus the once-per-version guard here. The native API reports
/// neither presentation nor the user's choice, so no logic depends on an "outcome".
@Observable
final class RatingPromptCoordinator {
  /// Balanced-profile thresholds (F-6.03 acceptance criteria).
  static let minInstallAgeDays = 7
  static let minDistinctLogDays = 3
  static let minLoggedExpenses = 10

  /// Transient and **not** persisted: set when an eligible log occurs, cleared after
  /// the root presenter requests a review. Observed by `ratingPromptPresenter()`.
  var isRequestPending = false

  private let state: RatingPromptState
  private let analytics: any AnalyticsClient
  private let calendar: Calendar

  init(
    state: RatingPromptState,
    analytics: any AnalyticsClient,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.state = state
    self.analytics = analytics
    self.calendar = calendar
  }

  /// Records a successful **Add-mode** expense log and advances eligibility.
  ///
  /// - Parameters:
  ///   - isActiveBudget: Whether the parent budget is in the `.active` lifecycle state.
  ///   - remainingIsNonNegative: Whether the budget's current-period Remaining is ≥ 0
  ///     after the save (the "positive moment" gate).
  func recordExpenseLogged(
    isActiveBudget: Bool,
    remainingIsNonNegative: Bool,
    now: Date = Date(),
    appVersion: String = RatingPromptCoordinator.currentAppVersion
  ) {
    advanceCounters(now: now)

    let thresholdsMet =
      installAgeDays(now: now) >= Self.minInstallAgeDays
        && state.distinctLogDayCount >= Self.minDistinctLogDays
        && state.loggedExpenseCount >= Self.minLoggedExpenses
    let positiveMoment = isActiveBudget && remainingIsNonNegative
    let eligible = thresholdsMet && positiveMoment

    if eligible, state.firstEligibleAt == nil {
      state.firstEligibleAt = now
      analytics.track(AnalyticsEvent.ratingPromptEligible)
      analytics.setRatingPromptFirstEligible(now)
    }

    if eligible, state.lastRequestedVersion != appVersion {
      isRequestPending = true
    }
  }

  /// Called by the root presenter immediately after invoking `requestReview`.
  /// Records the requested version (the once-per-version guard), clears the pending
  /// flag, and fires `rating_prompt_requested`.
  func consumePendingRequest(
    now: Date = Date(),
    appVersion: String = RatingPromptCoordinator.currentAppVersion
  ) {
    guard isRequestPending else { return }
    isRequestPending = false
    state.lastRequestedVersion = appVersion
    analytics.track(
      AnalyticsEvent.ratingPromptRequested,
      properties: [
        AnalyticsProperty.timeSinceFirstEligibleBucket:
          Self.timeSinceFirstEligibleBucket(firstEligibleAt: state.firstEligibleAt, now: now),
      ]
    )
    analytics.setRatingPromptLastRequested(now)
  }

  // MARK: - Private

  private func advanceCounters(now: Date) {
    state.loggedExpenseCount += 1
    let dayStart = calendar.startOfDay(for: now)
    if let last = state.lastLogDayStart {
      if !calendar.isDate(last, inSameDayAs: dayStart) {
        state.distinctLogDayCount += 1
        state.lastLogDayStart = dayStart
      }
    } else {
      state.distinctLogDayCount += 1
      state.lastLogDayStart = dayStart
    }
  }

  private func installAgeDays(now: Date) -> Int {
    calendar.dateComponents([.day], from: state.installedAt, to: now).day ?? 0
  }

  // MARK: - Pure decision helpers (extracted for testability)

  /// Whether the root presenter should request a review right now. Pure so the
  /// gating is unit-testable; the actual `requestReview()` call and `consume` stay
  /// in `RatingPromptPresenter`. The sheet gate is what defers the prompt until the
  /// Add Expense sheet has dismissed.
  static func shouldRequestReview(
    isRequestPending: Bool,
    sheetIsPresented: Bool,
    sceneIsActive: Bool
  ) -> Bool {
    isRequestPending && !sheetIsPresented && sceneIsActive
  }

  /// Derives the rating-prompt signals for a just-saved expense, or `nil` when the
  /// log must not feed the prompt (edit mode, or no owning budget). Pure so the
  /// `AddEditExpenseView` hook stays a thin call; the snapshot is computed exactly
  /// as the live UI would.
  static func expenseLogSignals(
    isAddMode: Bool,
    budget: Budget?,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent,
    weekStart: Weekday
  ) -> (isActiveBudget: Bool, remainingIsNonNegative: Bool)? {
    guard isAddMode, let budget else { return nil }
    let snapshot = BudgetCalculator.snapshot(
      budget: budget, expenses: budget.expenseItems, now: now, calendar: calendar, weekStart: weekStart
    )
    return (snapshot.lifecycleState == .active, snapshot.remaining >= 0)
  }

  // MARK: - Helpers

  static var currentAppVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
  }

  /// Buckets the gap between first-eligibility and the request. Coarse on purpose
  /// (no raw timestamps reach analytics).
  static func timeSinceFirstEligibleBucket(firstEligibleAt: Date?, now: Date) -> String {
    guard let firstEligibleAt else { return "<1d" }
    let days = now.timeIntervalSince(firstEligibleAt) / 86400
    return switch days {
    case ..<1: "<1d"
    case ..<7: "<7d"
    case ..<30: "<30d"
    default: "≥30d"
    }
  }
}
