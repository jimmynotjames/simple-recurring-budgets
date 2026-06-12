import Foundation

/// The lifecycle classification of a `Budget` at a given instant.
enum BudgetLifecycleState: Equatable {
  case preStart // now < effectiveStartDate
  case active // budget is running and current period is not paused
  case paused // current period falls inside a paused stretch
  case postEnd // now >= effectiveEndExclusive (day after endDate)
}

/// The pure, immutable snapshot of a `Budget`'s financial state at a given instant.
///
/// Computed by `BudgetCalculator.snapshot(...)` — the single read entry point.
/// No SwiftData types are mutated to produce this value.
struct BudgetSnapshot: Equatable {
  /// Lifecycle classification at the snapshot instant.
  let lifecycleState: BudgetLifecycleState

  /// Allocation in effect for the period containing the snapshot instant.
  let effectiveAllocation: Decimal

  /// Remaining for the current period (`effectiveAllocation − net expenses`).
  /// `0` for `.preStart` and `.paused` states.
  let remaining: Decimal

  /// Signed cumulative carry-over (walker sum + current-period spillover).
  /// `nil` for `.specificDates` budgets — F-2.08 hides the carry-over chip for that
  /// type, which both surfaces implement by passing
  /// `isCarryOverEnabled: budget.isCarryOverEnabled && !isSpecificDates` into
  /// `StatusChipRow` (see `BudgetDetailView.headerRow` and `BudgetRowView`).
  /// `BudgetLifecycleResult.carryOverAmount` flattens this `nil` → `0`; the flattened
  /// value is never rendered because the chip is hidden upstream.
  let carryOver: Decimal?

  /// Inclusive start of the effective current period.
  let effectivePeriodStart: Date

  /// Exclusive end of the effective current period.
  let effectivePeriodEnd: Date
}
