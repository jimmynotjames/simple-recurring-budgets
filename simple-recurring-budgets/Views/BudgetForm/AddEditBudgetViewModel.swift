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
  /// Optional decorative icon (a single emoji) prefixing the name; `nil` = none.
  var icon: String?
  var allocation: Decimal?
  var currencyCode: String

  /// Selected period. In Add mode, switching resets `startDate` / `endDate` to the
  /// per-period anchor defaults (F-2.03; see `onPeriodChange`). Edit mode locks the chip, so `didSet` short-circuits.
  var period: BudgetPeriod {
    didSet {
      guard period != oldValue, !isEditing else { return }
      onPeriodChange()
    }
  }

  var isCarryOverEnabled: Bool

  /// Window start. Recurring types are pre-filled in Add mode (daily → today; weekly /
  /// biweekly → most recent `weekStartDay`-aligned date; monthly → first of the month);
  /// `.specificDates` requires a pick before Save enables.
  ///
  /// Moving it past `endDate` snaps `endDate` forward to keep the window duration (Apple
  /// Calendar pattern). `didSet` doesn't fire during `init`, so seeding both dates in
  /// Edit mode is safe.
  var startDate: Date? {
    didSet {
      guard let newStart = startDate, let end = endDate, newStart > end else { return }
      let originalStart = oldValue ?? newStart
      let duration = end.timeIntervalSince(originalStart)
      endDate = newStart.addingTimeInterval(max(duration, 0))
    }
  }

  /// Window end. `nil` means no terminal date (recurring only); required for `.specificDates`.
  var endDate: Date?

  private let mode: Mode

  /// Captured at Add-mode `init` for `onPeriodChange` to recompute `startDate`. `nil` in
  /// Edit mode, where it's never read (the period chip is locked); `defaultStartDate`'s
  /// weekly/biweekly branches `preconditionFailure` so an unintended Edit-mode hit
  /// surfaces instead of mis-anchoring.
  private let weekStartDay: Weekday?

  // MARK: - Mode introspection

  var isEditing: Bool {
    if case .edit = mode {
      return true
    }
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

  /// Expenses dated before the drafted `startDate` (Edit mode only). They stay in the
  /// list but are excluded from carry-over and remaining.
  var orphanedExpenseCount: Int {
    guard case let .edit(budget) = mode, let start = startDate else { return 0 }
    return budget.expenseItems.count(where: { $0.date < start })
  }

  /// Edit mode, biweekly, drafted `startDate` differs from persisted: gates the Save-time
  /// re-anchor confirmation. Only biweekly grids anchor to `startDate` (weekly uses the
  /// global week-start; daily/monthly are unaffected).
  var isBiweeklyStartDateEdited: Bool {
    guard case let .edit(budget) = mode, period == .biweekly, let start = startDate else { return false }
    let normalized = Calendar.autoupdatingCurrent.startOfDay(for: start)
    return budget.startDate != normalized
  }

  // MARK: - Init (Add mode)

  init(settings: AppSettings) {
    name = ""
    icon = nil
    allocation = nil
    currencyCode = Locale.current.currency?.identifier ?? "USD"
    period = .daily
    isCarryOverEnabled = settings.defaultCarryOverEnabled
    weekStartDay = settings.weekStartDay
    // Pre-fills the default (.daily) period so the Schedule summary reads "Starts {today}";
    // later period changes re-anchor via `onPeriodChange`.
    startDate = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    endDate = nil
    mode = .add
  }

  // MARK: - Init (Edit mode)

  init(editing budget: Budget) {
    name = budget.name
    icon = budget.icon
    allocation = budget.currentAllocation
    currencyCode = budget.currencyCode
    period = budget.periodEnum
    isCarryOverEnabled = budget.isCarryOverEnabled
    startDate = budget.startDate
    endDate = budget.endDate
    weekStartDay = nil // never read in Edit mode (period chip is locked)
    mode = .edit(budget)
  }

  // MARK: - Delete

  func delete(context: ModelContext) throws {
    try delete(context: context, analytics: ConsoleAnalyticsClient())
  }

  func delete(context: ModelContext, analytics: any AnalyticsClient) throws {
    guard case let .edit(budget) = mode else { return }
    Logger.ui.debug(
      "ui.action: deleteBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let props = budgetEventProperties(budget: budget)
    context.delete(budget)
    try context.saveChanges(operation: .budgetDelete, analytics: analytics)
    // Analytics fires only after a successful save.
    analytics.track(AnalyticsEvent.budgetDeleted, properties: props)
    analytics.refreshCohortPeopleProperties(budgets: budgetCohortInfos(context: context))
  }

  // MARK: - Save

  func save(context: ModelContext) throws {
    try save(
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
  ) throws {
    switch mode {
    case .add:
      try saveNew(context: context, analytics: analytics, settings: settings, router: router)
    case let .edit(budget):
      try saveEdit(budget: budget, context: context, analytics: analytics, settings: settings)
    }
  }

  // MARK: - Save helpers

  private func saveNew(
    context: ModelContext,
    analytics: any AnalyticsClient,
    settings: AppSettings,
    router: Router
  ) throws {
    guard canSave, let allocation else { return }

    let now = Date()
    let calendar = Calendar.autoupdatingCurrent

    // `startDate` is pre-filled by init and re-anchored by `onPeriodChange`, so it's
    // non-nil here. The saved value (possibly user-overridden via Schedule) is the cycle
    // anchor (F-7.05) read by `Budget.effectiveStartDate` and the calculator. `endDate` is
    // optional for recurring types; `canSave` requires it for `.specificDates`.
    guard let pickedStart = startDate else { return }
    let computedStartDate = calendar.startOfDay(for: pickedStart)
    let computedEndDate: Date? = endDate.map { calendar.startOfDay(for: $0) }

    let budgetCountBefore = (try? context.fetchCount(FetchDescriptor<Budget>())) ?? 0
    let isFirst = budgetCountBefore == 0

    // Clamp carry-over off for `.specificDates`: the UI hides the toggle, so the in-memory
    // value can be a stale session default. Without it the row persists `true`, polluting
    // analytics and Mixpanel cohort properties that read `isCarryOverEnabled` directly
    // (the calculator already ignores it for this period type).
    let resolvedCarryOver = period == .specificDates ? false : isCarryOverEnabled
    let budget = Budget(
      name: name,
      currencyCode: currencyCode,
      period: period,
      isCarryOverEnabled: resolvedCarryOver,
      icon: icon
    )
    budget.startDate = computedStartDate
    budget.endDate = computedEndDate
    budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0
    context.insert(budget)

    // Initial AllocationChange goes in the same save.
    let initialChange = AllocationChange(effectiveFrom: computedStartDate, amount: allocation, lastModified: now)
    initialChange.budget = budget
    context.insert(initialChange)

    try context.saveChanges(operation: .budgetCreate, analytics: analytics)

    // Analytics fires only after a successful save.
    var props = budgetEventProperties(budget: budget)
    props[AnalyticsProperty.isFirstBudget] = isFirst
    if isFirst {
      let elapsed = Date().timeIntervalSince(settings.analyticsFirstOpenAt)
      props[AnalyticsProperty.timeSinceFirstAppOpenBucket] = timeSinceFirstOpenBucket(
        seconds: elapsed
      )
    }
    analytics.track(AnalyticsEvent.budgetCreated, properties: props)

    analytics.refreshSuperProperties()
    analytics.refreshCohortPeopleProperties(budgets: budgetCohortInfos(context: context))

    let jurisdiction = ConsentJurisdiction.kind(for: Locale.current.region?.identifier)
    if jurisdiction == .required, !settings.analyticsOptInExplicitlySet {
      router.sheet = .analyticsConsent
    }
  }

  private func saveEdit(
    budget: Budget,
    context: ModelContext,
    analytics: any AnalyticsClient,
    settings: AppSettings
  ) throws {
    // Only allocation/start/end changes become `budget_edited` flags (F-8.02; see
    // `docs/analytics-spec.md` §10.1). The name, icon, currency, and carry-over locals
    // exist solely for the aggregate `changed` gate below: F-8.02 doesn't surface them,
    // so revisit if F-8.02 expands to cover them.
    var nameChanged = false
    var iconChanged = false
    var allocationChanged = false
    var currencyChanged = false
    var carryOverToggleChanged = false
    if budget.name != name {
      budget.name = name
      nameChanged = true
    }
    if budget.icon != icon {
      budget.icon = icon
      iconChanged = true
    }
    // Date edits MUST precede the allocation edit. A biweekly startDate edit re-anchors
    // the 14-day grid, and `applyAllocationEdit` keys the new amount on
    // `max(currentPeriodStart, effectiveStartDate)`, both computed from the budget's
    // startDate at that moment; dates first stamps the amount against the window the user
    // just chose. Weekly grids use the global weekStartDay, but the key's
    // effectiveStartDate still depends on the post-edit startDate, so the order matters.
    let dateEdits = applyDateEdits(to: budget)
    if let newAlloc = allocation, budget.currentAllocation != newAlloc {
      try BudgetLifecycleService.applyAllocationEdit(
        budget,
        newAmount: newAlloc,
        context: context,
        analytics: analytics,
        weekStart: settings.weekStartDay
      )
      allocationChanged = true
    }
    if budget.currencyCode != currencyCode {
      budget.currencyCode = currencyCode
      currencyChanged = true
    }
    if budget.isCarryOverEnabled != isCarryOverEnabled {
      budget.isCarryOverEnabled = isCarryOverEnabled
      carryOverToggleChanged = true
    }
    let changed = nameChanged || iconChanged || allocationChanged || currencyChanged
      || carryOverToggleChanged || dateEdits.startChanged || dateEdits.endChanged
    if changed {
      budget.lastModified = Date()
      try context.saveChanges(operation: .budgetEdit, analytics: analytics)
      // Analytics fires only after a successful save. Orphan count: expenses dated before
      // the written startDate. Recurring budgets always have one here (canSave, Add-mode
      // pre-fill, and period.didSet guarantee it); a nil startDate counts as zero.
      let orphanedCount: Int = if let s = budget.startDate {
        budget.expenseItems.count(where: { $0.date < s })
      } else {
        0
      }
      analytics.track(
        AnalyticsEvent.budgetEdited,
        properties: budgetEventProperties(
          budget: budget,
          allocationChanged: allocationChanged,
          startDateChanged: dateEdits.startChanged,
          endDateChanged: dateEdits.endChanged,
          orphanedExpenseCount: orphanedCount
        )
      )
      analytics.refreshCohortPeopleProperties(budgets: budgetCohortInfos(context: context))
    }
  }

  // MARK: - Private helpers

  /// Add-mode hook on period chip change: resets `startDate` / `endDate` to the new
  /// period's defaults so the Schedule disclosure or Dates card stays coherent. Never
  /// runs in Edit mode (chip locked).
  private func onPeriodChange() {
    switch period {
    case .specificDates:
      // Both required, no sensible default: the user picks.
      startDate = nil
      endDate = nil
    case .daily, .weekly, .biweekly, .monthly:
      startDate = defaultStartDate(for: period)
      endDate = nil
    }
  }

  /// Add-mode default `startDate` per period (F-2.03), called only from `onPeriodChange`:
  /// - `.daily` → start of today.
  /// - `.weekly` / `.biweekly` → most recent `weekStartDay`-aligned date at or before today
  ///   (needs the captured `weekStartDay`, which Edit mode lacks; it can't get here).
  /// - `.monthly` → first of the current month.
  /// - `.specificDates` → unreachable: `onPeriodChange` clears both dates instead.
  private func defaultStartDate(for period: BudgetPeriod) -> Date {
    let now = Date()
    let calendar = Calendar.autoupdatingCurrent
    switch period {
    case .daily:
      return calendar.startOfDay(for: now)
    case .weekly, .biweekly:
      guard let weekStartDay else {
        preconditionFailure(
          "defaultStartDate called for \(period) without a captured weekStartDay — this should be unreachable from Edit mode (period chip is locked)."
        )
      }
      return Self.mostRecentWeekStart(weekStartDay, now: now, calendar: calendar)
    case .monthly:
      var comps = calendar.dateComponents([.year, .month], from: now)
      comps.day = 1; comps.hour = 0; comps.minute = 0; comps.second = 0
      return calendar.date(from: comps)!
    case .specificDates:
      preconditionFailure(
        "defaultStartDate has no value for .specificDates — onPeriodChange clears both dates instead. A hit here is a regression in onPeriodChange."
      )
    }
  }

  /// Re-anchors the Add-mode weekly draft `startDate` to the latest `weekStart` at or before
  /// today when the global week-start day changes (same alignment as `onPeriodChange`).
  /// No-op in Edit mode (the existing `startDate` is user data) and for non-weekly periods.
  func realignWeeklyStartDate(to weekStart: Weekday) {
    guard !isEditing, period == .weekly else { return }
    startDate = Self.mostRecentWeekStart(weekStart)
  }

  /// Latest `weekStart` at or before `now`, at start of day. Shared by `defaultStartDate`
  /// and `realignWeeklyStartDate` so the two anchoring paths can't drift.
  static func mostRecentWeekStart(
    _ weekStart: Weekday,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> Date {
    let dayStart = calendar.startOfDay(for: now)
    let weekday = calendar.component(.weekday, from: dayStart)
    let daysBack = (weekday - weekStart.rawValue + 7) % 7
    return calendar.date(byAdding: .day, value: -daysBack, to: dayStart)!
  }

  /// Applies Edit-mode `startDate` / `endDate` diffs (normalized to start of day before
  /// comparing); returns which fields changed, for the F-8.02 `budget_edited` flags.
  ///
  /// A `.specificDates` startDate change also calls `realignMostRecentAllocationChange`
  /// so the single-period algorithm reads the new window (F-2.08 latest wins).
  ///
  /// Recurring types update only `Budget.startDate`; leaving `AllocationChange` history
  /// alone is deliberate, not an omission. The `allocationInEffect` fallback
  /// (`Domain/AllocationInEffect.swift`) extends the earliest row's amount backward past
  /// its `effectiveFrom`, so back-dating credits the original allocation automatically;
  /// forward-dating works because `last(where: effectiveFrom <= date)` still matches the
  /// original row. For weekly/biweekly the new `startDate.weekday` also becomes the cycle
  /// anchor per F-7.05, an intended consequence of the edit.
  private func applyDateEdits(to budget: Budget) -> (startChanged: Bool, endChanged: Bool) {
    let calendar = Calendar.autoupdatingCurrent
    let now = Date()
    var startChanged = false
    var endChanged = false
    if let s = startDate {
      let normalized = calendar.startOfDay(for: s)
      if budget.startDate != normalized {
        budget.startDate = normalized
        if period == .specificDates {
          realignMostRecentAllocationChange(on: budget, to: normalized, now: now)
        }
        startChanged = true
      }
    }
    if let e = endDate {
      let normalized = calendar.startOfDay(for: e)
      if budget.endDate != normalized {
        budget.endDate = normalized
        endChanged = true
      }
    } else if budget.endDate != nil {
      // Cleared optional end date (recurring only; `canSave` requires both dates for
      // `.specificDates`).
      budget.endDate = nil
      endChanged = true
    }
    return (startChanged, endChanged)
  }

  /// Moves the most recent `AllocationChange.effectiveFrom` to `newStartDate` after a
  /// `.specificDates` startDate edit (single-period semantics per F-2.08). No-op without allocation rows, which a
  /// saved budget always has.
  private func realignMostRecentAllocationChange(on budget: Budget, to newStartDate: Date, now: Date) {
    guard let mostRecent = budget.mostRecentAllocationChange else { return }
    mostRecent.effectiveFrom = newStartDate
    mostRecent.lastModified = now
  }

  private func budgetEventProperties(budget: Budget) -> [String: any Sendable] {
    let p = budget.periodEnum
    return [
      AnalyticsProperty.period: p.analyticsValue,
      AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
      AnalyticsProperty.currencyCode: budget.currencyCode,
      AnalyticsProperty.budgetName: budget.name,
      AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
    ]
  }

  /// `budgetEdited`-only variant adding the F-8.02 per-field change flags (`allocation_changed`,
  /// `start_date_changed`, `end_date_changed`); deliberately not sent on other events
  /// (see `docs/analytics-spec.md` §10.1). `orphanedExpenseCount` (post-save) is included
  /// only when > 0; an absent key means no orphaned state.
  private func budgetEventProperties(
    budget: Budget,
    allocationChanged: Bool,
    startDateChanged: Bool,
    endDateChanged: Bool,
    orphanedExpenseCount: Int
  ) -> [String: any Sendable] {
    var props = budgetEventProperties(budget: budget)
    props[AnalyticsProperty.allocationChanged] = allocationChanged
    props[AnalyticsProperty.startDateChanged] = startDateChanged
    props[AnalyticsProperty.endDateChanged] = endDateChanged
    if orphanedExpenseCount > 0 {
      props[AnalyticsProperty.orphanedExpenseCount] = orphanedExpenseCount
    }
    return props
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
