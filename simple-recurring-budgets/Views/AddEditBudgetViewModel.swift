import Foundation
import Observation
import OSLog
import SwiftData

@Observable
@MainActor
final class AddEditBudgetViewModel {
  // MARK: - Mode

  private enum Mode {
    case add
    case edit(Budget)
  }

  // MARK: - Draft state

  var name: String
  var allocation: Decimal?
  var currencyCode: String
  var period: BudgetPeriod
  var isCarryOverEnabled: Bool

  private let mode: Mode

  // MARK: - Mode introspection

  var isEditing: Bool {
    if case .edit = mode { return true }
    return false
  }

  // MARK: - Validation

  var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (allocation ?? 0) > 0
  }

  // MARK: - Init (Add mode)

  /// Seeds Add-mode defaults from `AppSettings`. Does NOT retain a reference to `settings`
  /// after initialisation (reads `defaultCarryOverEnabled` once and captures the value).
  init(settings: AppSettings) {
    name = ""
    allocation = nil
    currencyCode = Locale.current.currency?.identifier ?? "USD"
    period = .daily
    isCarryOverEnabled = settings.defaultCarryOverEnabled
    mode = .add
  }

  // MARK: - Init (Edit mode)

  init(editing budget: Budget) {
    name = budget.name
    allocation = budget.allocation
    currencyCode = budget.currencyCode
    period = BudgetPeriod(rawValue: budget.period) ?? .daily
    isCarryOverEnabled = budget.isCarryOverEnabled
    mode = .edit(budget)
  }

  // MARK: - Delete

  /// Convenience overload used by tests and call sites that do not yet have an
  /// `AnalyticsClient` in scope. Routes to `delete(context:analytics:)`.
  func delete(context: ModelContext) {
    delete(context: context, analytics: ConsoleAnalyticsClient())
  }

  // TODO: If we eventually create a BudgetView that navigates to this screen, that may also need to be popped off nav stack on deletion.
  func delete(context: ModelContext, analytics: any AnalyticsClient) {
    guard case let .edit(budget) = mode else { return }
    Logger.ui.debug(
      "ui.action: deleteBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    // Capture snapshot BEFORE deletion — entity is unusable after save.
    let props = budgetEventProperties(budget: budget)
    context.delete(budget)
    try? context.save()
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    analytics.track(AnalyticsEvent.budgetDeleted, properties: props)
  }

  // MARK: - Save

  /// Convenience overload used by tests and call sites that do not yet have an
  /// `AnalyticsClient`/`AppSettings`/`Router` in scope. Routes to the full overload.
  func save(context: ModelContext) {
    save(
      context: context,
      analytics: ConsoleAnalyticsClient(),
      settings: AppSettings(),
      router: Router()
    )
  }

  /// Persists the draft to `context`. In Add mode, inserts a new `Budget`; in Edit
  /// mode, applies only the fields that actually changed so other mutable properties
  /// (carry-over amounts, sort order, etc.) are untouched. The view reads
  /// `@Environment(\.modelContext)` and passes it here; the VM never stores `context`.
  func save(
    context: ModelContext,
    analytics: any AnalyticsClient,
    settings: AppSettings,
    router: Router
  ) {
    switch mode {
    case .add:
      saveNew(context: context, analytics: analytics, settings: settings, router: router)
    case let .edit(budget):
      saveEdit(budget: budget, context: context, analytics: analytics)
    }
  }

  // MARK: - Save helpers

  private func saveNew(
    context: ModelContext,
    analytics: any AnalyticsClient,
    settings: AppSettings,
    router: Router
  ) {
    guard canSave, let allocation else { return }

    // Compute is_first_budget BEFORE inserting so the count reflects the current state.
    let budgetCountBefore = (try? context.fetchCount(FetchDescriptor<Budget>())) ?? 0
    let isFirst = budgetCountBefore == 0

    let budget = Budget(
      name: name,
      allocation: allocation,
      currencyCode: currencyCode,
      period: period,
      resetCadence: nil, // keeps the paused `.never` default from Budget.init
      isCarryOverEnabled: isCarryOverEnabled
    )
    budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0
    context.insert(budget)
    try? context.save()

    // Fire budget_created.
    var props = budgetEventProperties(budget: budget)
    props[AnalyticsProperty.isFirstBudget] = isFirst
    if isFirst {
      let elapsed = Date().timeIntervalSince(settings.analyticsFirstOpenAt)
      props[AnalyticsProperty.timeSinceFirstAppOpenBucket] = timeSinceFirstOpenBucket(
        seconds: elapsed
      )
    }
    analytics.track(AnalyticsEvent.budgetCreated, properties: props)

    // Refresh cohort people properties with the updated budget list.
    if let client = analytics as? MixpanelAnalyticsClient {
      let infos = budgetCohortInfos(context: context)
      client.refreshSuperProperties()
      client.refreshCohortPeopleProperties(budgets: infos)
    }

    // First-run consent sheet trigger (§7.2): strict-opt-in jurisdiction and
    // the user has not yet made an explicit analytics decision.
    let jurisdiction = ConsentJurisdiction.kind(for: Locale.current.region?.identifier)
    if jurisdiction == .required, !settings.analyticsOptInExplicitlySet {
      router.sheet = .analyticsConsent
    }
  }

  private func saveEdit(
    budget: Budget,
    context: ModelContext,
    analytics: any AnalyticsClient
  ) {
    var changed = false
    if budget.name != name {
      budget.name = name
      changed = true
    }
    if let newAlloc = allocation, budget.allocation != newAlloc {
      budget.allocation = newAlloc
      changed = true
    }
    if budget.currencyCode != currencyCode {
      budget.currencyCode = currencyCode
      changed = true
    }
    if budget.period != period.rawValue {
      budget.period = period.rawValue
      changed = true
    }
    if budget.isCarryOverEnabled != isCarryOverEnabled {
      budget.isCarryOverEnabled = isCarryOverEnabled
      changed = true
    }
    if changed {
      budget.lastModified = Date()
      try? context.save()
      analytics.track(
        AnalyticsEvent.budgetEdited,
        properties: budgetEventProperties(budget: budget)
      )
      if let client = analytics as? MixpanelAnalyticsClient {
        let infos = budgetCohortInfos(context: context)
        client.refreshCohortPeopleProperties(budgets: infos)
      }
    }
  }

  // MARK: - Private helpers

  private func budgetEventProperties(budget: Budget) -> [String: any Sendable] {
    let p = BudgetPeriod(rawValue: budget.period) ?? .daily
    return [
      AnalyticsProperty.period: p.analyticsValue,
      AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
      AnalyticsProperty.currencyCode: budget.currencyCode,
      AnalyticsProperty.budgetName: budget.name,
      AnalyticsProperty.budgetAllocationAmount: (budget.allocation as NSDecimalNumber).doubleValue,
    ]
  }

  private func budgetCohortInfos(context: ModelContext) -> [BudgetCohortInfo] {
    let descriptor = FetchDescriptor<Budget>()
    let budgets = (try? context.fetch(descriptor)) ?? []
    return budgets.map {
      BudgetCohortInfo(
        currencyCode: $0.currencyCode,
        periodRawValue: $0.period,
        isCarryOverEnabled: $0.isCarryOverEnabled
      )
    }
  }
}
