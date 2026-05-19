import Foundation
import SwiftData

/// A recurring (or one-shot) budget that tracks spending over repeating periods.
///
/// All monetary values use `Decimal`. The `period` property is stored as its `String` raw
/// value for human-readable CloudKit records. Allocation history lives in `AllocationChange`
/// child rows; lifecycle pause/resume history lives in `LifecycleEvent` child rows.
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

  /// When the budget begins. Semantically always populated for a saved budget; stored as
  /// `Date?` only for CloudKit optionality. Read-time fallback: `createdAt`.
  var startDate: Date?
  /// When the budget stops calculating (terminal, no resume). Genuinely optional for
  /// recurring budgets; required for `.specificDates`.
  var endDate: Date?
  /// The most recent manual Reset Carry-Over or Reset Budget timestamp.
  /// `nil` means no manual reset has occurred.
  var lastResetDate: Date?

  var isCarryOverEnabled: Bool = true

  /// CloudKit requires every relationship to be optional. Use `allocationChanges` in app
  /// code — it always returns a non-optional array.
  @Relationship(deleteRule: .cascade, inverse: \AllocationChange.budget)
  var allocationChangesStorage: [AllocationChange]?

  /// CloudKit requires every relationship to be optional. Use `lifecycleEvents` in app
  /// code — it always returns a non-optional array.
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

  /// The effective start date for math: `startDate` when populated, otherwise `createdAt`.
  /// Single source of truth — never read `startDate ?? createdAt` directly elsewhere.
  ///
  /// `startDate` is stored as `Date?` only for CloudKit optionality; semantically it is
  /// always populated for a saved budget. The `createdAt` fallback exists in case a sync
  /// race delivers a budget before its `startDate` field arrives. For biweekly budgets,
  /// silently anchoring to a different date can shift cycle boundaries — keeping the
  /// fallback centralized here makes the failure mode easier to spot and instrument.
  ///
  /// **Important:** this property returns the raw `Date` (which may carry a time-of-day
  /// component when the fallback to `createdAt` fires). Callers doing period math must
  /// wrap with `calendar.startOfDay(for:)` to get a day-aligned anchor — see
  /// `BudgetCalculator` and `BudgetLifecycleService.applyAllocationEdit` for the
  /// canonical pattern. UI callers (display labels, date-picker bounds) may use it as-is.
  var effectiveStartDate: Date {
    startDate ?? createdAt
  }

  /// Whether the budget's `[effectiveStartDate, endDate]` window is well-ordered.
  /// `true` when `endDate` is nil (recurring) or when `endDate >= effectiveStartDate`
  /// (`.specificDates`). An inverted window is a data-integrity violation — typically
  /// from a partial CloudKit sync — and callers building date ranges should assert
  /// before constructing a `ClosedRange` that would trap on an inverted bound.
  var isWindowValid: Bool {
    endDate.map { $0 >= effectiveStartDate } ?? true
  }

  /// The most-recent allocation amount by `(effectiveFrom, lastModified)`. Used for
  /// display contexts (analytics, RemainingBar denominator) where a quick "current
  /// allocation" lookup is sufficient. The algorithm uses `allocationInEffect(at:history:)`
  /// for period-accurate values.
  var currentAllocation: Decimal {
    allocationChanges.max { lhs, rhs in
      if lhs.effectiveFrom != rhs.effectiveFrom { return lhs.effectiveFrom < rhs.effectiveFrom }
      return lhs.lastModified < rhs.lastModified
    }?.amount ?? 0
  }

  init(
    name: String = "Budget",
    currencyCode: String = Locale.current.currency?.identifier ?? "USD",
    period: BudgetPeriod = .daily,
    isCarryOverEnabled: Bool = true
  ) {
    self.name = name
    self.currencyCode = currencyCode
    self.period = period.rawValue
    self.isCarryOverEnabled = isCarryOverEnabled
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
