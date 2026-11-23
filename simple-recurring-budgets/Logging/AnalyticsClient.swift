import Foundation

/// Product analytics abstraction: routes business-metric events to the configured backend (Mixpanel in
/// production, console print in debug). Spec: `docs/analytics-spec.md`.
///
/// Diagnostic/operational events are logged via `OSLog.Logger` (`AppLoggers.swift`) and never pass through
/// this protocol; the two channels are independent.
///
/// **Allow/deny contract:**
/// - Allowed per event: categorical Budget properties (`period`, `carry_over_enabled`, `currency_code`),
///   bucketed counts, Boolean flags, and the two accepted-risk exceptions (`budget_name`,
///   `budget_allocation_amount`).
/// - **Hard ban**: no `ExpenseItem` field (name, amount, date, notes) is ever transmitted by value; no free
///   text other than `budget_name`; no money-shaped value other than `budget_allocation_amount`.
protocol AnalyticsClient: AnyObject, Sendable {
  func track(_ event: String, properties: [String: any Sendable]?)
  func identify(_ distinctId: String?)
  func reset()

  // MARK: Super / people-property surface

  // Default no-op implementations below let clients without a people/super-property concept
  // (ConsoleAnalyticsClient) skip these. Call sites MUST go through the protocol, never downcast to
  // `MixpanelAnalyticsClient`, so test doubles can observe the calls.

  /// Re-registers the super properties on the live backend; call after any write that affects a super-property value.
  func refreshSuperProperties()
  /// Recomputes and persists the cohort people-properties from the current Budget collection; call after `budget_created` / `budget_edited` / `budget_deleted`.
  func refreshCohortPeopleProperties(budgets: [BudgetCohortInfo])
  /// Sets the `analytics_opt_in_at` people property; call on the opt-in transition, after the first opted-in `track` has lazily initialised the SDK.
  func setAnalyticsOptInAt()
  /// Sets the `rating_prompt_first_eligible_at` people property (set-once).
  func setRatingPromptFirstEligible(_ date: Date)
  /// Refreshes the `rating_prompt_last_requested_at` people property.
  func setRatingPromptLastRequested(_ date: Date)
}

extension AnalyticsClient {
  func track(_ event: String) {
    track(event, properties: nil)
  }

  // Default no-ops: only backends with a people/super-property concept override these.
  func refreshSuperProperties() {}
  func refreshCohortPeopleProperties(budgets _: [BudgetCohortInfo]) {}
  func setAnalyticsOptInAt() {}
  func setRatingPromptFirstEligible(_: Date) {}
  func setRatingPromptLastRequested(_: Date) {}
}

// MARK: - BudgetCohortInfo

/// Snapshot of the Budget properties needed for cohort people-properties; callers build it from their `Budget` models and pass it to `refreshCohortPeopleProperties(budgets:)`.
struct BudgetCohortInfo {
  let currencyCode: String
  let periodRawValue: String
  let isCarryOverEnabled: Bool
}

// MARK: - Canonical event names

/// Canonical event-name constants (`snake_case`). Use at every call site, never inline literals, so typos fail at compile time.
enum AnalyticsEvent {
  nonisolated static let appOpened = "app_opened"
  nonisolated static let budgetCreated = "budget_created"
  nonisolated static let budgetEdited = "budget_edited"
  nonisolated static let budgetDeleted = "budget_deleted"
  nonisolated static let budgetReset = "budget_reset"
  nonisolated static let budgetPaused = "budget_paused"
  nonisolated static let budgetResumed = "budget_resumed"
  nonisolated static let carryOverReset = "carry_over_reset"
  nonisolated static let expenseLogged = "expense_logged"
  nonisolated static let expenseEdited = "expense_edited"
  nonisolated static let expenseDeleted = "expense_deleted"
  /// Fired when the user taps a Recents suggestion tile in Add Expense. Properties are categorical/bucketed only; no `ExpenseItem` field is transmitted.
  nonisolated static let expenseRecentReused = "expense_recent_reused"
  nonisolated static let settingsOpened = "settings_opened"
  nonisolated static let settingChanged = "setting_changed"
  nonisolated static let analyticsConsentChanged = "analytics_consent_changed"
  /// Fired by the shared persistence-save helper when `context.save()` throws. The single product-stream
  /// event sourced from the OSLog-shaped failure path; payload restricted to `operation`, `error_domain`,
  /// `error_code`.
  nonisolated static let persistenceSaveFailed = "persistence_save_failed"

  // MARK: Rating prompt

  // There is intentionally no `rating_prompt_shown` / `rating_prompt_resolved` event: the native
  // `requestReview` API reports neither presentation nor outcome. Do not reintroduce them.

  /// Fired **once per user**, the first time the rating-prompt eligibility
  /// thresholds are met (gated by the persisted first-eligible timestamp).
  nonisolated static let ratingPromptEligible = "rating_prompt_eligible"
  /// Fired when the app calls the native `requestReview`. De-duplicated per app
  /// version (matching the once-per-version guard). No outcome is observable.
  nonisolated static let ratingPromptRequested = "rating_prompt_requested"
}

// MARK: - Canonical property keys

/// Canonical property-key constants matching the spec's `snake_case` names. Use at every `track(_:properties:)` call site, never inline literals.
enum AnalyticsProperty {
  // MARK: Per-event — budget_*

  nonisolated static let period = "period"
  nonisolated static let carryOverEnabled = "carry_over_enabled"
  nonisolated static let currencyCode = "currency_code"
  nonisolated static let isFirstBudget = "is_first_budget"
  nonisolated static let timeSinceFirstAppOpenBucket = "time_since_first_app_open_bucket"
  /// Accepted-risk allow-listed property.
  nonisolated static let budgetName = "budget_name"
  /// Accepted-risk allow-listed property. Always paired with `currency_code`.
  nonisolated static let budgetAllocationAmount = "budget_allocation_amount"

  // MARK: Per-event — budget_edited only (per-field change flags)

  // Show which fields the user edited (name vs date vs allocation). Never emitted on `budget_created`, where everything is new.

  nonisolated static let allocationChanged = "allocation_changed"
  nonisolated static let startDateChanged = "start_date_changed"
  nonisolated static let endDateChanged = "end_date_changed"
  /// Count of expenses dated before the new `Budget.startDate` after an Edit-mode
  /// save. Present iff > 0; absence denotes "save did not produce an orphaned state".
  nonisolated static let orphanedExpenseCount = "orphaned_expense_count"

  // MARK: Per-event — expense_*

  nonisolated static let isAddFunds = "is_add_funds"
  nonisolated static let fromScreen = "from_screen"
  nonisolated static let timeSinceBudgetCreatedBucket = "time_since_budget_created_bucket"

  // MARK: Per-event — expense_recent_reused

  // Categorical/bucketed Recents-reuse signal; never includes the description string or amount.

  /// Bucketed number of Recents tiles visible in the section at tap time
  /// (e.g., `"1"`, `"2-3"`, `"4-7"`, `"8-15"`).
  nonisolated static let recentsVisibleCount = "recents_visible_count"
  /// Bucketed 0-indexed position of the tapped tile in the visible row
  /// (e.g., `"0"`, `"1"`, `"2-4"`, `"5+"`).
  nonisolated static let recentsTapPosition = "recents_tap_position"
  /// Bucketed length of the user's typed Description query at the moment of the tap
  /// (e.g., `"0"`, `"1-2"`, `"3+"`). Answers whether the user typed-then-tapped or
  /// open-and-tapped.
  nonisolated static let nameQueryLength = "name_query_length"

  // MARK: Per-event — setting_changed

  nonisolated static let settingName = "setting_name"
  nonisolated static let newValue = "new_value"
  nonisolated static let oldValue = "old_value"

  // MARK: Per-event — persistence_save_failed

  /// `PersistenceOperation` raw value (snake_case enum, e.g. `budget_create`).
  nonisolated static let operation = "operation"
  /// `NSError.domain` of the underlying SwiftData failure.
  nonisolated static let errorDomain = "error_domain"
  /// `NSError.code` of the underlying SwiftData failure.
  nonisolated static let errorCode = "error_code"

  // MARK: Per-event — rating_prompt_requested

  /// Bucketed gap between the first-eligible timestamp and the request
  /// (`<1d` / `<7d` / `<30d` / `≥30d`). Never a raw timestamp.
  nonisolated static let timeSinceFirstEligibleBucket = "time_since_first_eligible_bucket"

  // MARK: Super properties

  nonisolated static let appVersion = "app_version"
  nonisolated static let appBuild = "app_build"
  nonisolated static let deviceClass = "device_class"
  nonisolated static let locale = "locale"
  nonisolated static let region = "region"
  nonisolated static let weekStartDay = "week_start_day"
  nonisolated static let currencyDisplayPreference = "currency_display_preference"
  nonisolated static let icloudState = "icloud_state"
  nonisolated static let budgetsCountBucket = "budgets_count_bucket"
  nonisolated static let carryOverDefaultEnabled = "carry_over_default_enabled"
  nonisolated static let consentJurisdiction = "consent_jurisdiction"

  // MARK: People properties

  nonisolated static let firstSeenAt = "first_seen_at"
  nonisolated static let analyticsOptInAt = "analytics_opt_in_at"
  nonisolated static let lastAppOpenAt = "last_app_open_at"
  nonisolated static let dominantPeriod = "dominant_period"
  nonisolated static let usesCarryOver = "uses_carry_over"
  nonisolated static let hasDisabledCarryOver = "has_disabled_carry_over"
  nonisolated static let budgetsWithCarryOverOnCountBucket = "budgets_with_carry_over_on_count_bucket"
  nonisolated static let defaultCurrencyCode = "default_currency_code"

  // MARK: People properties — rating prompt

  /// Timestamp set the first time the rating-prompt threshold is met (set-once).
  nonisolated static let ratingPromptFirstEligibleAt = "rating_prompt_first_eligible_at"
  /// Timestamp refreshed each time the app calls `requestReview`. No outcome is stored.
  nonisolated static let ratingPromptLastRequestedAt = "rating_prompt_last_requested_at"
}
