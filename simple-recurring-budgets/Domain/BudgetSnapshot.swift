import Foundation

/// The lifecycle classification of a `Budget` at a given instant.
enum BudgetLifecycleState: Equatable {
  case preStart // now < effectiveStartDate
  case active // budget is running and current period is not paused
  case paused // current period falls inside a paused stretch
  case postEnd // now >= effectiveEndExclusive (day after endDate)
}

/// Pure, immutable snapshot of a `Budget`'s financial state at an instant, produced by `BudgetCalculator.snapshot(...)`.
struct BudgetSnapshot: Equatable {
  /// Lifecycle classification at the snapshot instant.
  let lifecycleState: BudgetLifecycleState

  /// Allocation in effect for the period containing the snapshot instant.
  let effectiveAllocation: Decimal

  /// Remaining for the current period (`effectiveAllocation − net expenses`).
  /// `0` for `.preStart` and `.paused` states.
  let remaining: Decimal

  /// Signed cumulative carry-over (walker sum + current-period spillover). `nil` for `.specificDates`: the
  /// carry-over chip is hidden for that type per F-2.08 (callers pass `isCarryOverEnabled: budget.isCarryOverEnabled &&
  /// !isSpecificDates` to `StatusChipRow`). `BudgetLifecycleResult.carryOverAmount` flattens `nil` to `0`,
  /// never rendered since the chip is hidden upstream.
  let carryOver: Decimal?

  /// Inclusive start of the effective current period.
  let effectivePeriodStart: Date

  /// Exclusive end of the effective current period.
  let effectivePeriodEnd: Date
}
