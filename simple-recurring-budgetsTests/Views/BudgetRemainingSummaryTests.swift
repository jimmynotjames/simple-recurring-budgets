import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - BudgetRemainingSummary.accessibilityLabel

/// Tests cover the 8 case paths of the static a11y label helper (4-case switch
/// on `(isSpecificDates, isOverBudget)` × name/no-name prefix), plus the
/// `remaining == 0` boundary and the negative-amount sign-flip. New cases
/// added in `unify-inactive-budget-states` cover the `.preStart` and `.postEnd`
/// inactive reasons.
///
/// Assertions are structural (prefix + substring) rather than full-string
/// equality so they remain stable under copy tweaks and locale changes in the
/// test environment.
struct BudgetSummaryAccessibilityLabelTests {
  // MARK: - Recurring × under budget

  @Test func recurring_underBudget_withName_prefixesNameAndAnnouncesRemainingPeriod() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 248.50,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("remaining"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("over budget"))
  }

  @Test func recurring_underBudget_withoutName_announcesRemainingPeriodOnly() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 248.50,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("remaining"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("over budget"))
  }

  // MARK: - Recurring × over budget

  @Test func recurring_overBudget_withName_prefixesNameAndAnnouncesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: -57.25,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("over budget"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("remaining"))
  }

  @Test func recurring_overBudget_withoutName_announcesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: -57.25,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("over budget"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("remaining"))
  }

  // MARK: - Specific Dates × under budget

  @Test func specificDates_underBudget_withName_prefixesNameAndAnnouncesInlineDescriptor() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Vacation",
      remaining: 941.00,
      allocation: 1000,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Vacation, "))
    #expect(label.contains("remaining"))
    #expect(label.contains("in this window"))
    // Specific Dates grammar omits the trailing "period" wrapper.
    #expect(!label.contains("this monthly period"))
    #expect(!label.contains("over budget"))
  }

  @Test func specificDates_underBudget_withoutName_announcesInlineDescriptorOnly() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 941.00,
      allocation: 1000,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("remaining"))
    #expect(label.contains("in this window"))
    #expect(!label.contains("over budget"))
  }

  // MARK: - Specific Dates × over budget

  @Test func specificDates_overBudget_withName_prefixesNameAndAnnouncesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Vacation",
      remaining: -120.00,
      allocation: 1000,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Vacation, "))
    #expect(label.contains("over budget"))
    #expect(label.contains("in this window"))
    #expect(!label.contains("remaining"))
  }

  @Test func specificDates_overBudget_withoutName_announcesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: -120.00,
      allocation: 1000,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("over budget"))
    #expect(label.contains("in this window"))
    #expect(!label.contains("remaining"))
  }

  // MARK: - Edge cases

  @Test func zeroRemaining_classifiedAsRemainingNotOverBudget() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 0,
      allocation: 25,
      isSpecificDates: false,
      periodInlineLabel: "daily",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.contains("remaining"))
    #expect(!label.contains("over budget"))
  }

  @Test func namePrefix_usesCommaAndSpaceVerbatim() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Foo",
      remaining: 100,
      allocation: 200,
      isSpecificDates: false,
      periodInlineLabel: "weekly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Foo, "))
  }

  @Test func overBudget_formattedAmountIsPositive() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Foo",
      remaining: -57.25,
      allocation: 200,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    // The body after the name prefix must not begin with a minus sign — the
    // helper flips the sign so the announcement reads "$57.25 over budget…",
    // not "-$57.25 over budget…".
    let body = label.dropFirst("Foo, ".count)
    #expect(!body.hasPrefix("-"))
    #expect(body.contains("57"))
  }

  // MARK: - Inactive states (preStart, postEnd)

  @Test func preStart_withName_announcesAllocationStartsDate() {
    let startDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 0,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .preStart(startDate: startDate)
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("starts"))
    #expect(label.contains("monthly"))
    #expect(!label.contains("remaining"))
    #expect(!label.contains("over budget"))
    // Allocation, not remaining, drives the announcement.
    #expect(label.contains("400") || label.contains("$400"))
  }

  @Test func preStart_withoutName_omitsPrefix() {
    let startDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 0,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .preStart(startDate: startDate)
    )
    // Without a budget name, the label must not begin with "<name>, ". The
    // formatted date inside the body may contain ", " (e.g. "Jun 1, 2026"), so
    // we cannot use `contains(", ")` as the assertion — check the prefix shape
    // directly by confirming the first character is a digit / currency symbol.
    let first = label.first ?? " "
    #expect(first.isNumber || first == "$" || first == "€" || first == "£")
    #expect(label.contains("starts"))
  }

  @Test func postEnd_withName_announcesAllocationEndedDate() {
    let endDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 42,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .postEnd(endDate: endDate)
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("ended"))
    #expect(label.contains("monthly"))
    #expect(!label.contains("remaining"))
    #expect(!label.contains("over budget"))
    // Allocation, not the final-period residual remaining, drives the announcement.
    #expect(label.contains("400") || label.contains("$400"))
  }

  @Test func postEnd_withoutName_omitsPrefix() {
    let endDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 42,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .postEnd(endDate: endDate)
    )
    // Same prefix-check rationale as preStart_withoutName_omitsPrefix.
    let first = label.first ?? " "
    #expect(first.isNumber || first == "$" || first == "€" || first == "£")
    #expect(label.contains("ended"))
  }

  // MARK: - Active state (no inactive reason)

  /// Verifies the "Active row is unaffected by inactive-state styling" scenario
  /// from `budgets-screen` / `budget-detail-screen` deltas: when `inactiveReason`
  /// is `nil`, the helper uses `remaining` (not `allocation`) and dispatches to
  /// the existing on-budget recurring key — not to any `.preStart` / `.postEnd`
  /// variant.
  @Test func active_inactiveReasonIsNil_usesRemainingNotAllocation() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 12.50,
      allocation: 400, // intentionally very different from remaining
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: nil
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("remaining"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    // Active path announces `remaining` (12.50), never the allocation (400).
    #expect(label.contains("12"))
    #expect(!label.contains("400"))
    // No inactive-state copy.
    #expect(!label.contains("starts"))
    #expect(!label.contains("ended"))
  }

  @Test func paused_fallsThroughToOnBudgetKey() {
    let pausedSince = Date(timeIntervalSinceReferenceDate: 800_500_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 7.50,
      allocation: 25,
      isSpecificDates: false,
      periodInlineLabel: "daily",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .paused(since: pausedSince)
    )
    // Paused case reuses the existing on-budget recurring key; no separate
    // paused-state suffix is introduced by `unify-inactive-budget-states`.
    #expect(label.contains("remaining"))
    #expect(label.contains("daily"))
    #expect(!label.contains("starts"))
    #expect(!label.contains("ended"))
  }
}
