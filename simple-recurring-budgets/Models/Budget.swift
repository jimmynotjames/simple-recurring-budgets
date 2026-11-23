import Foundation
import SwiftData

/// A recurring (or one-shot) budget. Monetary values use `Decimal`. `period` is stored as its `String` raw
/// value for human-readable CloudKit records. Allocation history lives in `AllocationChange` rows;
/// pause/resume history in `LifecycleEvent` rows.
@Model
final class Budget {
  var id: UUID = UUID()
  var name: String = "Budget"
  var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
  /// Stored as `BudgetPeriod.rawValue`.
  var period: String = BudgetPeriod.daily.rawValue
  var sortOrder: Int = 0
  var createdAt: Date = Date()
  var lastModified: Date = Date()

  /// When the budget begins. Always populated for a saved budget; `Date?` only for CloudKit optionality.
  /// Read-time fallback: `createdAt`.
  var startDate: Date?
  /// When the budget stops calculating (terminal, no resume). Optional for recurring budgets; required for
  /// `.specificDates`.
  ///
  /// **`endDate` is the inclusive last *day* of the window.** Stored as `startOfDay(picked)`, but the whole day
  /// belongs to the budget: expenses can be logged anytime on `endDate`, and the budget becomes `.postEnd`
  /// only once `now >= startOfDay(endDate + 1 day)`. `BudgetCalculator` computes
  /// `effectiveEndExclusive = startOfDay(endDate + 1 day)` and uses `< effectiveEndExclusive` for inclusion.
  /// Date-range UI (e.g. `AddEditExpenseView.dateRange`) must clamp its upper bound to the last moment of
  /// `endDate`'s day, not `startOfDay(endDate)`, which excludes most of the last day from the picker.
  var endDate: Date?
  /// The most recent manual Reset Carry-Over or Reset Budget timestamp; `nil` if none.
  var lastResetDate: Date?

  var isCarryOverEnabled: Bool = true

  /// Optional decorative icon prefixed to the name on budget surfaces (Budgets list, detail header); `nil` if
  /// unpicked. Stored as `String?` for CloudKit optionality; by convention a single emoji grapheme (the picker
  /// enforces it). Named `icon`, not `emoji`, so the column survives a broader icon source.
  var icon: String?

  /// CloudKit requires optional relationships; use `allocationChanges` in app code (always non-optional).
  @Relationship(deleteRule: .cascade, inverse: \AllocationChange.budget)
  var allocationChangesStorage: [AllocationChange]?

  /// CloudKit requires optional relationships; use `lifecycleEvents` in app code (always non-optional).
  @Relationship(deleteRule: .cascade, inverse: \LifecycleEvent.budget)
  var lifecycleEventsStorage: [LifecycleEvent]?

  /// CloudKit requires every relationship to be optional. Use `expenseItems` in app code.
  @Relationship(deleteRule: .cascade, inverse: \ExpenseItem.budget)
  var expenses: [ExpenseItem]?

  // MARK: - Non-optional computed accessors

  var allocationChanges: [AllocationChange] {
    allocationChangesStorage ?? []
  }

  var lifecycleEvents: [LifecycleEvent] {
    lifecycleEventsStorage ?? []
  }

  var expenseItems: [ExpenseItem] {
    get { expenses ?? [] }
    set { expenses = newValue }
  }

  /// The effective start date for math: `startDate` when populated, else `createdAt`. Single source of truth:
  /// never read `startDate ?? createdAt` elsewhere.
  ///
  /// The `createdAt` fallback covers a sync race delivering a budget before its `startDate` arrives. For
  /// biweekly budgets, silently anchoring to a different date can shift cycle boundaries; keeping the fallback
  /// centralized here makes that failure easier to spot and instrument.
  ///
  /// **Important:** returns the raw `Date`, which may carry a time of day when the fallback fires. Period math
  /// must wrap it in `calendar.startOfDay(for:)` (see `BudgetCalculator`,
  /// `BudgetLifecycleService.applyAllocationEdit`). UI callers (labels, picker bounds) may use it as-is.
  var effectiveStartDate: Date {
    startDate ?? createdAt
  }

  /// The `BudgetPeriod` for this budget, centralising `BudgetPeriod(rawValue:) ?? .daily` so every call site
  /// shares one fallback for unrecognised raw values (schema-migration compatibility). Sites that must *bail*
  /// on an unrecognised value should call `BudgetPeriod(rawValue:)` directly.
  var periodEnum: BudgetPeriod {
    BudgetPeriod(rawValue: period) ?? .daily
  }

  /// Whether the `[effectiveStartDate, endDate]` window is well-ordered: `true` when `endDate` is nil
  /// (recurring) or `>= effectiveStartDate`. An inverted window is a data-integrity violation (typically a
  /// partial CloudKit sync); callers building date ranges should assert before constructing a `ClosedRange`
  /// that would trap.
  var isWindowValid: Bool {
    endDate.map { $0 >= effectiveStartDate } ?? true
  }

  /// The newest `AllocationChange` by `(effectiveFrom, lastModified)`, the canonical sort key wherever the
  /// algorithm or UI needs the current allocation row. `nil` only when `allocationChanges` is empty
  /// (shouldn't happen for a saved budget).
  ///
  /// Centralised so display, write-path, and lifecycle code share one tiebreak: see `currentAllocation`,
  /// `BudgetLifecycleService.applyAllocationEdit`'s specificDates branch, and
  /// `AddEditBudgetViewModel.applySpecificDatesDateEdits`.
  var mostRecentAllocationChange: AllocationChange? {
    allocationChanges.max { lhs, rhs in
      if lhs.effectiveFrom != rhs.effectiveFrom {
        return lhs.effectiveFrom < rhs.effectiveFrom
      }
      return lhs.lastModified < rhs.lastModified
    }
  }

  /// The most recent allocation amount, for display (analytics, RemainingBar denominator). The algorithm uses
  /// `allocationInEffect(at:history:)` for period-accurate values.
  var currentAllocation: Decimal {
    mostRecentAllocationChange?.amount ?? 0
  }

  init(
    name: String = "Budget",
    currencyCode: String = Locale.current.currency?.identifier ?? "USD",
    period: BudgetPeriod = .daily,
    isCarryOverEnabled: Bool = true,
    icon: String? = nil
  ) {
    self.name = name
    self.currencyCode = currencyCode
    self.period = period.rawValue
    self.isCarryOverEnabled = isCarryOverEnabled
    self.icon = icon
  }
}

extension Budget {
  /// Returns the next `sortOrder` for a **new** budget: `0` if none exist, else `max + 1`.
  /// Call before `context.insert(_:)` so the fetch does not include the new instance.
  static func nextSortOrder(for context: ModelContext) throws -> Int {
    var descriptor = FetchDescriptor<Budget>()
    descriptor.sortBy = [SortDescriptor(\.sortOrder, order: .reverse)]
    descriptor.fetchLimit = 1
    guard let maxBudget = try context.fetch(descriptor).first else { return 0 }
    return maxBudget.sortOrder + 1
  }
}
