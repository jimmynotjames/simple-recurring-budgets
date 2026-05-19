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
  /// Specific Dates window start. `nil` for recurring period types; required when `period == .specificDates`.
  ///
  /// When this is set to a date that crosses past `endDate`, `endDate` is snapped
  /// forward to preserve the original window duration (Apple Calendar pattern).
  /// `didSet` does not fire during `init`, so seeding both dates in Edit mode is safe.
  var startDate: Date? {
    didSet {
      guard let newStart = startDate, let end = endDate, newStart > end else { return }
      let originalStart = oldValue ?? newStart
      let duration = end.timeIntervalSince(originalStart)
      endDate = newStart.addingTimeInterval(max(duration, 0))
    }
  }

  /// Specific Dates window end. `nil` for recurring period types; required when `period == .specificDates`.
  var endDate: Date?

  private let mode: Mode

  // MARK: - Mode introspection

  var isEditing: Bool {
    if case .edit = mode { return true }
    return false
  }

  // MARK: - Validation

  var canSave: Bool {
    let nameOK = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let allocOK = (allocation ?? 0) > 0
    if period == .specificDates {
      guard let s = startDate, let e = endDate else { return false }
      return nameOK && allocOK && s <= e
    }
    return nameOK && allocOK
  }

  // MARK: - Init (Add mode)

  init(settings: AppSettings) {
    name = ""
    allocation = nil
    currencyCode = Locale.current.currency?.identifier ?? "USD"
    period = .daily
    isCarryOverEnabled = settings.defaultCarryOverEnabled
    startDate = nil
    endDate = nil
    mode = .add
  }

  // MARK: - Init (Edit mode)

  init(editing budget: Budget) {
    name = budget.name
    allocation = budget.currentAllocation
    currencyCode = budget.currencyCode
    period = BudgetPeriod(rawValue: budget.period) ?? .daily
    isCarryOverEnabled = budget.isCarryOverEnabled
    startDate = budget.startDate
    endDate = budget.endDate
    mode = .edit(budget)
  }

  // MARK: - Delete

  func delete(context: ModelContext) {
    delete(context: context, analytics: ConsoleAnalyticsClient())
  }

  func delete(context: ModelContext, analytics: any AnalyticsClient) {
    guard case let .edit(budget) = mode else { return }
    Logger.ui.debug(
      "ui.action: deleteBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let props = budgetEventProperties(budget: budget)
    context.delete(budget)
    try? context.save()
    analytics.track(AnalyticsEvent.budgetDeleted, properties: props)
  }

  // MARK: - Save

  func save(context: ModelContext) {
    save(
      context: context,
      analytics: ConsoleAnalyticsClient(),
      settings: AppSettings(),
      router: Router()
    )
  }

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
      saveEdit(budget: budget, context: context, analytics: analytics, settings: settings)
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

    let now = Date()
    let calendar = Calendar.autoupdatingCurrent

    // Compute startDate per period type so AppSettings.weekStartDay anchors weekly/biweekly.
    let computedStartDate: Date
    let computedEndDate: Date?
    switch period {
    case .daily:
      computedStartDate = calendar.startOfDay(for: now)
      computedEndDate = nil

    case .weekly, .biweekly:
      // Most recent weekStartDay-aligned date at or before startOfDay(now).
      let dayStart = calendar.startOfDay(for: now)
      let weekday = calendar.component(.weekday, from: dayStart)
      let daysBack = (weekday - settings.weekStartDay.rawValue + 7) % 7
      computedStartDate = calendar.date(byAdding: .day, value: -daysBack, to: dayStart)!
      computedEndDate = nil

    case .monthly:
      var comps = calendar.dateComponents([.year, .month], from: now)
      comps.day = 1; comps.hour = 0; comps.minute = 0; comps.second = 0
      computedStartDate = calendar.date(from: comps)!
      computedEndDate = nil

    case .specificDates:
      // canSave gated both dates non-nil; defensive guards mirror the recurring guards.
      guard let s = startDate, let e = endDate else { return }
      computedStartDate = calendar.startOfDay(for: s)
      computedEndDate = calendar.startOfDay(for: e)
    }

    let budgetCountBefore = (try? context.fetchCount(FetchDescriptor<Budget>())) ?? 0
    let isFirst = budgetCountBefore == 0

    let budget = Budget(
      name: name,
      currencyCode: currencyCode,
      period: period,
      isCarryOverEnabled: isCarryOverEnabled
    )
    budget.startDate = computedStartDate
    budget.endDate = computedEndDate
    budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0
    context.insert(budget)

    // Insert the initial AllocationChange in the same save.
    let initialChange = AllocationChange(effectiveFrom: computedStartDate, amount: allocation, lastModified: now)
    initialChange.budget = budget
    context.insert(initialChange)

    try? context.save()

    var props = budgetEventProperties(budget: budget)
    props[AnalyticsProperty.isFirstBudget] = isFirst
    if isFirst {
      let elapsed = Date().timeIntervalSince(settings.analyticsFirstOpenAt)
      props[AnalyticsProperty.timeSinceFirstAppOpenBucket] = timeSinceFirstOpenBucket(
        seconds: elapsed
      )
    }
    analytics.track(AnalyticsEvent.budgetCreated, properties: props)

    if let client = analytics as? MixpanelAnalyticsClient {
      let infos = budgetCohortInfos(context: context)
      client.refreshSuperProperties()
      client.refreshCohortPeopleProperties(budgets: infos)
    }

    let jurisdiction = ConsentJurisdiction.kind(for: Locale.current.region?.identifier)
    if jurisdiction == .required, !settings.analyticsOptInExplicitlySet {
      router.sheet = .analyticsConsent
    }
  }

  private func saveEdit(
    budget: Budget,
    context: ModelContext,
    analytics: any AnalyticsClient,
    settings _: AppSettings
  ) {
    var changed = false
    if budget.name != name {
      budget.name = name
      changed = true
    }
    if let newAlloc = allocation, budget.currentAllocation != newAlloc {
      BudgetLifecycleService.applyAllocationEdit(
        budget,
        newAmount: newAlloc,
        context: context
      )
      changed = true
    }
    if budget.currencyCode != currencyCode {
      budget.currencyCode = currencyCode
      changed = true
    }
    if budget.isCarryOverEnabled != isCarryOverEnabled {
      budget.isCarryOverEnabled = isCarryOverEnabled
      changed = true
    }
    if period == .specificDates, applySpecificDatesDateEdits(to: budget) {
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

  /// Applies Edit-mode `startDate` / `endDate` diffs for `.specificDates` budgets.
  ///
  /// Normalizes drafts with `calendar.startOfDay(for:)` before comparison. When `startDate`
  /// changes, the most-recent `AllocationChange.effectiveFrom` is realigned to the new
  /// start so the algorithm reads the new window (latest-wins, single-period semantics
  /// per F-2.08).
  ///
  /// - Returns: `true` if any field was mutated, `false` otherwise.
  private func applySpecificDatesDateEdits(to budget: Budget) -> Bool {
    let calendar = Calendar.autoupdatingCurrent
    let now = Date()
    var changed = false
    if let s = startDate {
      let normalized = calendar.startOfDay(for: s)
      if budget.startDate != normalized {
        budget.startDate = normalized
        if let mostRecent = budget.allocationChanges.max(by: { lhs, rhs in
          if lhs.effectiveFrom != rhs.effectiveFrom { return lhs.effectiveFrom < rhs.effectiveFrom }
          return lhs.lastModified < rhs.lastModified
        }) {
          mostRecent.effectiveFrom = normalized
          mostRecent.lastModified = now
        }
        changed = true
      }
    }
    if let e = endDate {
      let normalized = calendar.startOfDay(for: e)
      if budget.endDate != normalized {
        budget.endDate = normalized
        changed = true
      }
    }
    return changed
  }

  private func budgetEventProperties(budget: Budget) -> [String: any Sendable] {
    let p = BudgetPeriod(rawValue: budget.period) ?? .daily
    return [
      AnalyticsProperty.period: p.analyticsValue,
      AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
      AnalyticsProperty.currencyCode: budget.currencyCode,
      AnalyticsProperty.budgetName: budget.name,
      AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
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
