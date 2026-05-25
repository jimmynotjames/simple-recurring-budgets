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
  /// Optional decorative icon (a single emoji) shown as a prefix of the name.
  /// `nil` = none. Bound to the budget icon picker on the Add/Edit screen.
  var icon: String?
  var allocation: Decimal?
  var currencyCode: String

  /// Selected budget period. In Add mode, switching periods resets `startDate` /
  /// `endDate` to per-period defaults (see `onPeriodChange`) — this gives the
  /// user a calm "Starts {date} · No end date" pre-fill they can ignore. In Edit
  /// mode the chip is locked, so the `didSet` short-circuits.
  var period: BudgetPeriod {
    didSet {
      guard period != oldValue, !isEditing else { return }
      onPeriodChange()
    }
  }

  var isCarryOverEnabled: Bool

  /// Budget window start. For recurring period types, pre-filled in Add mode per
  /// the per-period anchor rules in F-2.03 (daily → start of today; weekly/biweekly →
  /// most recent `weekStartDay`-aligned date; monthly → first of current month). For
  /// `.specificDates` the user must pick a value before Save is enabled.
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

  /// Budget window end. Optional for recurring period types (the budget has no
  /// terminal date when `nil`); required when `period == .specificDates`.
  var endDate: Date?

  private let mode: Mode

  /// Captured at Add-mode `init` time and used by `onPeriodChange` to recompute
  /// `startDate` when the user toggles between weekly/biweekly and other periods.
  /// `nil` in Edit mode (where the period chip is locked, so `onPeriodChange`
  /// never fires and this value is never read). `defaultStartDate(for:)`'s
  /// weekly/biweekly branches guard with `preconditionFailure` so an unintended
  /// Edit-mode hit surfaces immediately instead of producing wrong anchoring.
  private let weekStartDay: Weekday?

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

  /// Count of existing expenses on the bound budget whose `date` is before the
  /// currently-drafted `startDate`. Non-zero only in Edit mode when the user has
  /// moved the start forward past one or more logged expenses; those expenses
  /// will remain in the list but be excluded from carry-over and remaining.
  var orphanedExpenseCount: Int {
    guard case let .edit(budget) = mode, let start = startDate else { return 0 }
    return budget.expenseItems.count(where: { $0.date < start })
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
    // Pre-fill startDate for the default (.daily) period so the Schedule disclosure
    // can render a sensible summary ("Starts {today}") without the user touching it.
    // Subsequent period changes re-anchor via `onPeriodChange`.
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

    // `startDate` is pre-filled by Add-mode init and re-anchored by `onPeriodChange`
    // whenever the user toggles between period types, so it's always non-nil here.
    // For weekly/biweekly the user can also override the pre-filled anchor via the
    // Schedule disclosure — `Budget.effectiveStartDate` (and the calculator) reads
    // the saved `startDate` as the cycle anchor (F-7.05). `endDate` is optional for
    // recurring period types and required (by `canSave`) for `.specificDates`.
    guard let pickedStart = startDate else { return }
    let computedStartDate = calendar.startOfDay(for: pickedStart)
    let computedEndDate: Date? = endDate.map { calendar.startOfDay(for: $0) }

    let budgetCountBefore = (try? context.fetchCount(FetchDescriptor<Budget>())) ?? 0
    let isFirst = budgetCountBefore == 0

    // Force `isCarryOverEnabled = false` for `.specificDates`: the UI hides the toggle,
    // so the in-memory value can be stale from a pre-toggle session default. Without this
    // clamp, the persisted row carries a `true` that pollutes analytics events and
    // Mixpanel cohort properties that read `budget.isCarryOverEnabled` directly (the
    // calculator already ignores it for this period type — see BudgetCalculator §A.4.2).
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
    // Per-field diff locals: `allocationChanged`, `startChanged`, `endChanged`
    // feed the F-8.02 flags on `budget_edited` (see `docs/analytics-spec.md`
    // §10.1). `nameChanged`, `currencyChanged`, `carryOverToggleChanged` are
    // tracked only to compute the aggregate `changed` gate below — analytics
    // doesn't surface them per F-8.02 scope. `iconChanged` is likewise
    // gate-only (cosmetic field). Add a corresponding analytics property here if
    // F-8.02 ever expands to cover them.
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
    if let newAlloc = allocation, budget.currentAllocation != newAlloc {
      BudgetLifecycleService.applyAllocationEdit(
        budget,
        newAmount: newAlloc,
        context: context
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
    let dateEdits = applyDateEdits(to: budget)
    let changed = nameChanged || iconChanged || allocationChanged || currencyChanged
      || carryOverToggleChanged || dateEdits.startChanged || dateEdits.endChanged
    if changed {
      budget.lastModified = Date()
      try? context.save()
      // Post-save orphan count: expenses dated before the written Budget.startDate.
      // Recurring budgets always have a non-nil startDate here (the canSave gate +
      // Add-mode pre-fill + period.didSet re-anchoring guarantee it). For the
      // .specificDates case where startDate could theoretically be nil mid-edit,
      // the absence is treated as zero (the warning UI is recurring-only anyway).
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
      if let client = analytics as? MixpanelAnalyticsClient {
        let infos = budgetCohortInfos(context: context)
        client.refreshCohortPeopleProperties(budgets: infos)
      }
    }
  }

  // MARK: - Private helpers

  /// Add-mode hook fired when the user taps a different period chip. Resets
  /// `startDate` / `endDate` to the new period's defaults so the Schedule
  /// disclosure (recurring) or Dates card (Specific Dates) always renders a
  /// coherent state. Never runs in Edit mode (the chip is locked there).
  private func onPeriodChange() {
    switch period {
    case .specificDates:
      // Both dates are required and have no sensible default — let the user pick.
      startDate = nil
      endDate = nil
    case .daily, .weekly, .biweekly, .monthly:
      startDate = defaultStartDate(for: period)
      endDate = nil
    }
  }

  /// Per-period-type default for `startDate` in Add mode (F-2.03):
  /// - `.daily` → start of today.
  /// - `.weekly` / `.biweekly` → most recent `weekStartDay`-aligned date at or before today.
  /// - `.monthly` → first of the current month.
  /// - `.specificDates` → **unreachable.** `onPeriodChange` handles `.specificDates`
  ///   by clearing both dates instead of calling this method; a hit here means a
  ///   regression in `onPeriodChange`.
  ///
  /// Only called from `onPeriodChange` in Add mode. The weekly/biweekly branches
  /// require a captured `weekStartDay` — Edit-mode would have `nil` there but
  /// must never reach this method because the period chip is locked.
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
      let dayStart = calendar.startOfDay(for: now)
      let weekday = calendar.component(.weekday, from: dayStart)
      let daysBack = (weekday - weekStartDay.rawValue + 7) % 7
      return calendar.date(byAdding: .day, value: -daysBack, to: dayStart)!
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

  /// Applies Edit-mode `startDate` / `endDate` diffs for any period type.
  ///
  /// Both drafts are normalized with `calendar.startOfDay(for:)` before comparison.
  /// A `startDate` change on a `.specificDates` budget additionally triggers
  /// `realignMostRecentAllocationChange(to:on:)` so the single-period algorithm
  /// reads the new window (F-2.08 latest-wins semantics).
  ///
  /// For recurring period types, a `startDate` edit updates `Budget.startDate`
  /// only — the `AllocationChange` history is intentionally left alone. This is
  /// correct, not a TODO: the calculator's `allocationInEffect` fallback (see
  /// `Domain/AllocationInEffect.swift`, the "Falls back to the earliest row's
  /// amount" branch) extends the earliest row's amount backward to any
  /// `boundaryStart` that precedes its `effectiveFrom`, so back-dating
  /// automatically credits the original allocation to the new back-dated window
  /// without any data-mutation step. Forward-dating works symmetrically: the
  /// walker starts at the new (later) `effectiveStartDate` and the
  /// `AllocationChange` at the original earlier date still matches any query at
  /// the new boundaries via the usual `last(where: effectiveFrom <= date)` rule.
  /// For weekly/biweekly, `Budget.startDate.weekday` also becomes the cycle
  /// anchor per F-7.05 — that's a deliberate consequence of the edit, not an
  /// algorithm change.
  ///
  /// - Returns: A `(startChanged, endChanged)` tuple describing which date field
  ///   was mutated. Both flags are `false` when no field changed. Consumed by
  ///   `saveEdit` to feed the F-8.02 per-field flags on `budget_edited`.
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
      // User cleared an optional end date (recurring only — `.specificDates`
      // can't reach here because `canSave` requires both dates non-nil).
      budget.endDate = nil
      endChanged = true
    }
    return (startChanged, endChanged)
  }

  /// Realigns the most-recent `AllocationChange.effectiveFrom` to `newStartDate` so the
  /// algorithm reads the new window after a `.specificDates` startDate edit (latest-wins,
  /// single-period semantics per F-2.08). No-op when the budget has no allocation rows
  /// (should not happen for a saved budget).
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

  /// `budgetEdited`-only variant that appends the F-8.02 per-field change flags
  /// (`allocation_changed`, `start_date_changed`, `end_date_changed`) so analytics
  /// can distinguish a name edit from a date edit from an allocation edit. These
  /// flags are intentionally NOT emitted on `budgetCreated` (every field is "new"
  /// by definition there) or any other event — see `docs/analytics-spec.md` §10.1.
  ///
  /// The `orphanedExpenseCount` parameter (post-save state: number of expenses
  /// dated before the new `Budget.startDate`) is included only when > 0; absence
  /// of the key denotes "save did not produce an orphaned state".
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
